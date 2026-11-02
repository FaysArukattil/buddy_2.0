import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/onboarding/auth_wrapper.dart';
import 'package:buddy/services/currency_service.dart';
import 'package:buddy/data/countries_data.dart';

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

// Short CTAs on steps 1-3 keep momentum; the last CTA is the conversion moment.
const List<_StepMeta> _steps = [
  _StepMeta(
    headline: 'Where are you based?\nChoose your currency.',
    body:
        'Auto-tracking and money symbols will be tuned specifically for your country.',
    cta: 'Continue',
  ),
  _StepMeta(
    headline: 'Your spending\nlogs itself.',
    body:
        'Pay with any bank or wallet as usual. Buddy spots the payment alert and logs it for you.',
    cta: 'Continue',
  ),
  _StepMeta(
    headline: 'We never read\nyour OTPs.',
    body:
        'Alerts are filtered on your phone. Bank OTPs and personal chats are ignored.',
    cta: 'Continue',
  ),
  _StepMeta(
    headline: 'Every pro tool.\n{symbol}0 forever.',
    body:
        'Heatmaps, category insights and friend-debt tracking are unlocked from day one.',
    cta: 'Start tracking free',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const int _pageCount = 4;

  int _page = 0;
  int _direction = 1; // 1 = forward, -1 = backward
  bool _finishing = false;
  bool _reduceMotion = false;

  int _hubTab = 0;
  Timer? _hubTimer;

  // ── Country & Currency Selection State ──
  late CountryEntry _selectedCountry;
  final TextEditingController _countrySearchController =
      TextEditingController();
  late final FocusNode _countrySearchFocus;
  List<CountryEntry> _filteredCountries = List.of(CountriesData.all);

  /// One-shot timeline for stages 1 & 2 (plays once, then holds final state).
  late final AnimationController _stage;

  /// Slow breathing used by the CTA glow and the shield pulse.
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _selectedCountry =
        CountriesData.findByCountryCode(CurrencyService.countryCode);
    _filteredCountries = List.of(CountriesData.all);
    _countrySearchFocus = FocusNode();
    _countrySearchController.addListener(_onCountrySearchChanged);

    _stage = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();

    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    if (_page == 3) {
      _startHubTimer();
    }
  }

  void _onCountrySearchChanged() {
    setState(() {
      _filteredCountries =
          CountriesData.search(_countrySearchController.text);
    });
  }

  void _selectCountry(CountryEntry entry) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCountry = entry;
    });
    CurrencyService.setCountry(
      countryCode: entry.countryCode,
      currencyCode: entry.currencyCode,
      currencySymbol: entry.currencySymbol,
      localeCode: entry.localeCode,
    );
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
    _countrySearchController.removeListener(_onCountrySearchChanged);
    _countrySearchController.dispose();
    _countrySearchFocus.dispose();
    _hubTimer?.cancel();
    _stage.dispose();
    _ambient.dispose();
    super.dispose();
  }

  // ── Page 4 (index 3) auto-cycle (stops as soon as the user touches a tab) ──
  void _startHubTimer() {
    _hubTimer?.cancel();
    if (_reduceMotion) return;
    _hubTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (!mounted || _page != 3) return;
      setState(() => _hubTab = (_hubTab + 1) % 3);
    });
  }

  // ── Navigation ───────────────────────────────────────────────
  void _goTo(int target) {
    if (target < 0 || target >= _pageCount || target == _page) return;
    HapticFeedback.selectionClick();
    _countrySearchFocus.unfocus();
    setState(() {
      _direction = target > _page ? 1 : -1;
      _page = target;
      if (target == 3) _hubTab = 0;
    });

    _hubTimer?.cancel();
    if (target == 3) _startHubTimer();

    // Stages 1 & 2 use the one-shot timeline; stages 0 & 3 have interactive content
    if (_reduceMotion || target == 0 || target == 3) {
      _stage.value = 1;
    } else {
      _stage
        ..reset()
        ..forward();
    }
  }

  void _next() {
    if (_finishing) return;
    _countrySearchFocus.unfocus();
    HapticFeedback.lightImpact();
    if (_page < _pageCount - 1) {
      _goTo(_page + 1);
    } else {
      _finish();
    }
  }

  void _prev() {
    if (_page > 0 && !_finishing) {
      _countrySearchFocus.unfocus();
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
        final isLandscape =
            MediaQuery.orientationOf(ctx) == Orientation.landscape;
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
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
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
                SizedBox(height: isLandscape ? 10 : 20),
                Container(
                  width: isLandscape ? 48 : 64,
                  height: isLandscape ? 48 : 64,
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
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.white,
                    size: isLandscape ? 24 : 30,
                  ),
                ),
                SizedBox(height: isLandscape ? 10 : 16),
                Text(
                  'Allow notification access',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isLandscape ? 18 : 21,
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
                    fontSize: isLandscape ? 12.5 : 13.5,
                    height: 1.45,
                    color: AppColors.textSecondaryOf(ctx),
                  ),
                ),
                SizedBox(height: isLandscape ? 14 : 22),
                _GradientButton(
                  label: 'Allow & continue',
                  icon: Icons.bolt_rounded,
                  height: isLandscape ? 48 : 56,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: isLandscape ? 38 : 44,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(
                      'Not now',
                      style: TextStyle(
                        fontSize: isLandscape ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(ctx),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

    // Ensure the country selected on the onboarding screen is saved
    try {
      await CurrencyService.setCountry(
        countryCode: _selectedCountry.countryCode,
        currencyCode: _selectedCountry.currencyCode,
        currencySymbol: _selectedCountry.currencySymbol,
        localeCode: _selectedCountry.localeCode,
      );
    } catch (_) {}

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
    if (_page == 3 && (_hubTimer == null || !_hubTimer!.isActive)) {
      _startHubTimer();
    }
    final isDark = AppColors.isDark(context);
    final step = _steps[_page];

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.15,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _page == 0
            ? (isDark ? _kHeroDark.first : _kHeroLight.first)
            : AppColors.backgroundOf(context),
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          // The hero is dark in both themes, so status icons are always light.
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: _page == 0
                ? null
                : (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v < -240) {
                      // Swipe never triggers signup; only advances to the last page.
                      if (_page < _pageCount - 1) _next();
                    } else if (v > 240) {
                      _prev();
                    }
                  },
            child: OrientationBuilder(
              builder: (context, orientation) {
                final isLandscape = orientation == Orientation.landscape;
                if (_page == 0) {
                  return _buildCountrySelectionScreen(isDark,
                      isLandscape: isLandscape);
                }
                return isLandscape
                    ? _buildLandscapeContent(step, isDark)
                    : _buildPortraitContent(step, isDark);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitContent(_StepMeta step, bool isDark) {
    return Column(
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
    );
  }

  Widget _buildLandscapeContent(_StepMeta step, bool isDark) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _buildHero(isDark, isLandscape: true),
        ),
        Expanded(
          flex: 5,
          child: SafeArea(
            left: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Spacer(),
                            _buildCopy(step, isDark, isLandscape: true),
                            const SizedBox(height: 8),
                            _buildBottomDock(step, isDark, isLandscape: true),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Hero panel (same gradient + radius language as Home) ─────
  Widget _buildHero(bool isDark, {bool isLandscape = false}) {
    final colors = isDark ? _kHeroDark : _kHeroLight;
    return Container(
      width: double.infinity,
      height: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: isLandscape
            ? const BorderRadius.horizontal(right: Radius.circular(32))
            : const BorderRadius.vertical(bottom: Radius.circular(36)),
        boxShadow: [
          BoxShadow(
            color: _kInk.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: isLandscape ? const Offset(4, 0) : const Offset(0, 8),
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
            right: !isLandscape,
            child: Column(
              children: [
                _buildTopBar(isLandscape: isLandscape),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final w = isLandscape
                          ? 380.0
                          : math.min(
                              math.max(box.maxWidth - 40, 360.0), 460.0);
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          isLandscape ? 12 : 20,
                          2,
                          isLandscape ? 12 : 20,
                          isLandscape ? 10 : 22,
                        ),
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
  Widget _buildTopBar({bool isLandscape = false}) {
    final isLast = _page == _pageCount - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, isLandscape ? 2 : 6, 8, 0),
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
                        padding: EdgeInsets.symmetric(
                            vertical: isLandscape ? 8 : 14),
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
                    minimumSize: Size(48, isLandscape ? 36 : 44),
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
  Widget _buildCopy(_StepMeta step, bool isDark, {bool isLandscape = false}) {
    final sw = MediaQuery.sizeOf(context).width;
    final shortScreen = MediaQuery.sizeOf(context).height < 700;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 16 : 24,
        isLandscape ? 8 : (shortScreen ? 16 : 24),
        isLandscape ? 16 : 24,
        0,
      ),
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
                  step.headline.replaceAll('{symbol}', CurrencyService.symbol),
                  style: TextStyle(
                    fontSize: isLandscape
                        ? 22
                        : (sw < 360 || shortScreen ? 27 : 32),
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -0.8,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              SizedBox(height: isLandscape ? 6 : 10),
              Text(
                step.body,
                style: TextStyle(
                  fontSize: isLandscape ? 13 : (shortScreen ? 13.5 : 15),
                  fontWeight: FontWeight.w500,
                  height: isLandscape ? 1.35 : 1.42,
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
          child: _page == 1
              ? _stageAutoLog()
              : (_page == 2 ? _stagePrivacy() : _stageProHub()),
        ),
      ),
    );
  }

  // ── Bottom dock: CTA + secondary line ────────────────────────
  Widget _buildBottomDock(_StepMeta step, bool isDark,
      {bool isLandscape = false}) {
    final isLast = _page == _pageCount - 1;
    final muted = AppColors.textSecondaryOf(context);
    final accent = isDark ? AppColors.primary : const Color(0xFF1E5D57);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 16 : 24,
        isLandscape ? 10 : 18,
        isLandscape ? 16 : 24,
        isLandscape ? 4 : 6,
      ),
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
                height: isLandscape ? 48 : 56,
                labelKey: ValueKey('cta_$_page'),
                onTap: _finishing ? null : _next,
              );
            },
          ),
          SizedBox(height: isLandscape ? 2 : 4),
          SizedBox(
            height: isLandscape ? 32 : 40,
            child: isLast
                ? TextButton(
                    onPressed: _finishing ? null : _finish,
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have an account?  ',
                        style: TextStyle(
                          fontSize: isLandscape ? 12 : 13,
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
                        size: isLandscape ? 12 : 14,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Free forever. No ads. Private by design.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isLandscape ? 11 : 12,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
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
                            Flexible(
                              child: Container(
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: catColor,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
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
    final sampleMerchant =
        _sampleMerchantForCountry(_selectedCountry.countryCode);
    final sampleChannel =
        _sampleChannelForCountry(_selectedCountry.countryCode);
    final sampleAmount =
        _sampleAmountForCountry(_selectedCountry.currencyCode);
    final sampleTileAmount =
        _sampleShortAmountForCountry(_selectedCountry.currencyCode);

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
                            Text(
                              'Paid ${_selectedCountry.currencySymbol}$sampleAmount to $sampleMerchant via $sampleChannel',
                              style: const TextStyle(
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
                  title: sampleMerchant,
                  catColor: AppColors.getCategoryColor('Food & Dining'),
                  icon: Icons.restaurant_rounded,
                  category: 'Food & Dining',
                  time: 'Just now',
                  amount:
                      '-${_selectedCountry.currencySymbol}$sampleTileAmount',
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
    final sampleMerchant =
        _sampleMerchantForCountry(_selectedCountry.countryCode);
    final sampleChannel =
        _sampleChannelForCountry(_selectedCountry.countryCode);
    final sampleTileAmount =
        _sampleShortAmountForCountry(_selectedCountry.currencyCode);
    final isIndia = _selectedCountry.countryCode == 'IN';
    final paymentTitle = isIndia
        ? 'Paid ₹240 to Swiggy via UPI'
        : 'Paid ${_selectedCountry.currencySymbol}$sampleTileAmount to $sampleMerchant via $sampleChannel';
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
          bool isSwiggy = false,
        }) {
          final r = _seg(t, 0.15 + i * 0.22, 0.40 + i * 0.22);
          final struck = !allowed && r > 0.6;
          final badgeColor = allowed ? AppColors.success : _kExpenseOnHero;

          final iconWidget = isSwiggy
              ? Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFC8019),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x44FC8019),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: CustomPaint(
                      size: Size(18, 18),
                      painter: _SwiggyLogoPainter(color: Colors.white),
                    ),
                  ),
                )
              : Container(
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
                );

          final content = Row(
            children: [
              iconWidget,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
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
              title: 'Your login OTP is 482910',
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
              title: paymentTitle,
              sub: 'Verified bank transaction alert',
              badge: 'LOGGED',
              allowed: true,
              isSwiggy: isIndia,
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
    const tabs = ['Heatmaps', 'Borrow & Lend', 'Categories'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Same segmented-bar language as Home's Balance/Income/Expense toggle.
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.all(3.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double totalWidth = constraints.maxWidth;
              const int itemCount = 3;
              final double segWidth = totalWidth / itemCount;
              const double pillInset = 1.0;
              final double pillWidth = segWidth - (2 * pillInset);
              final double leftOffset = (_hubTab * segWidth + pillInset);

              Color c1, c2, borderC, glowC;
              if (_hubTab == 0) {
                c1 = Colors.white.withValues(alpha: 0.28);
                c2 = Colors.white.withValues(alpha: 0.15);
                borderC = Colors.white.withValues(alpha: 0.45);
                glowC = Colors.white.withValues(alpha: 0.15);
              } else if (_hubTab == 1) {
                c1 = AppColors.income.withValues(alpha: 0.38);
                c2 = AppColors.income.withValues(alpha: 0.22);
                borderC = AppColors.income.withValues(alpha: 0.60);
                glowC = AppColors.income.withValues(alpha: 0.25);
              } else {
                c1 = const Color(0xFFFF7A45).withValues(alpha: 0.38);
                c2 = const Color(0xFFFF7A45).withValues(alpha: 0.22);
                borderC = const Color(0xFFFF7A45).withValues(alpha: 0.60);
                glowC = const Color(0xFFFF7A45).withValues(alpha: 0.25);
              }

              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: leftOffset,
                    width: pillWidth,
                    top: 1,
                    bottom: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c1, c2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: borderC,
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: glowC,
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(tabs.length, (i) {
                      final selected = _hubTab == i;
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _hubTab = i);
                            _startHubTimer();
                          },
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                tabs[i],
                                maxLines: 1,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.60),
                                  fontSize: 12.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
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
          height: 42,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dayNum,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                amount,
                style: TextStyle(
                  fontSize: 9.5,
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
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 15,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$month spend heatmap',
                  style: TextStyle(
                    fontSize: 13.5,
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
              _miniStat('Daily avg', '${CurrencyService.symbol}448', AppColors.secondary),
              const SizedBox(width: 8),
              _miniStat('Peak ($short 5)', '${CurrencyService.symbol}4,337', AppColors.expense),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8.5),
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
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
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
    const accentStripeColor = Color(0xFF00897B);

    return _solid(
      minHeight: _kPreviewMinH,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(
                      Icons.handshake_rounded,
                      size: 15,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Borrow & Lend Tracker',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.north_east_rounded, size: 12, color: AppColors.income),
                  const SizedBox(width: 2),
                  Text(
                    '+${CurrencyService.symbol}1,450',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.income,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Exact DebtCard look from borrow_lend_screen.dart:
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.borderOf(context).withValues(alpha: 0.5),
                width: 1.0,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF26A69A), Color(0xFF00897B)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'RK',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: -1,
                                  bottom: -1,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceOf(context),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF00897B),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Rahul Kumar',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimaryOf(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Lent • Dinner bill split',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '+${CurrencyService.symbol}1,450',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.income,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00897B).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF00897B)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Due in 3 days',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF00897B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '1-Tap Settle',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 4.0,
                    child: ColoredBox(color: accentStripeColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPreviewCard() {
    final food = AppColors.getCategoryColor('Food & Dining');
    final groceries = AppColors.getCategoryColor('Groceries');
    final isDark = AppColors.isDark(context);

    Widget categoryRow({
      required String name,
      required double amount,
      required double pct,
      required int count,
      required Color color,
      required IconData icon,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.22 : 0.15),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: color.withValues(alpha: isDark ? 0.35 : 0.30),
                  width: 1.0,
                ),
              ),
              child: Center(
                child: Icon(icon, color: color, size: 18),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        '${CurrencyService.symbol}${amount.toInt()}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct / 100.0,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 4.0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${pct.toInt()}% of total • $count transactions',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _solid(
      minHeight: _kPreviewMinH,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      Icons.donut_large_rounded,
                      size: 15,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Top Spending Categories',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
              Text(
                '${CurrencyService.symbol}12,554 total',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          categoryRow(
            name: 'Food & Dining',
            amount: 5240,
            pct: 42,
            count: 14,
            color: food,
            icon: Icons.restaurant_rounded,
          ),
          categoryRow(
            name: 'Groceries',
            amount: 3890,
            pct: 31,
            count: 6,
            color: groceries,
            icon: Icons.shopping_basket_rounded,
          ),
        ],
      ),
    );
  }

  /// "₹0 forever" board (high-contrast, attractive, doesn't blend with background).
  Widget _buildZeroPill() {
    final isDark = AppColors.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14302C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kIncomeOnHero,
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: _kIncomeOnHero.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kIncomeOnHero, Color(0xFF00BFA5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: _kIncomeOnHero.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '${CurrencyService.symbol}0 / forever',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: _kInk,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: _kIncomeOnHero,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'No subscriptions. No ads.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : _kInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Every pro feature unlocked from day one.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : AppColors.textSecondaryOf(context),
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
  // Dynamic Country / Currency Mock Samples
  // ─────────────────────────────────────────────────────────────
  String _sampleMerchantForCountry(String countryCode) {
    return switch (countryCode) {
      'IN' => 'Fresh Basket Supermarket',
      'AE' => 'Carrefour Supermarket',
      'SA' => 'Panda Hypermarket',
      'US' => 'Trader Joe\'s',
      'GB' => 'Sainsbury\'s Local',
      'CA' => 'Loblaws Supermarket',
      'AU' => 'Woolworths Metro',
      'SG' => 'FairPrice Supermarket',
      'PK' => 'Imtiaz Super Market',
      'BD' => 'Shwapno Superstore',
      'NG' => 'Shoprite Supermarket',
      'KE' => 'Naivas Supermarket',
      'ID' => 'Indomaret Fresh',
      'MY' => 'Jaya Grocer',
      'PH' => 'SM Supermarket',
      'JP' => '7-Eleven Ginza',
      'KR' => 'CU Mart Seoul',
      'DE' || 'FR' || 'ES' || 'IT' || 'NL' || 'IE' || 'BE' || 'AT' || 'PT' => 'Carrefour Express',
      'BR' => 'Pão de Açúcar',
      'MX' => 'OXXO Super',
      'ZA' => 'Pick n Pay',
      'NZ' => 'Countdown Metro',
      _ => 'Local Grocery Market',
    };
  }

  String _sampleChannelForCountry(String countryCode) {
    return switch (countryCode) {
      'IN' => 'UPI',
      'AE' => 'Debit Card',
      'SA' => 'mada',
      'US' => 'Apple Pay',
      'GB' => 'Contactless',
      'CA' => 'Interac',
      'AU' => 'Tap & Pay',
      'SG' => 'PayNow',
      'PK' => 'Raast',
      'BD' => 'bKash',
      'NG' => 'Transfer',
      'KE' => 'M-PESA',
      'ID' => 'QRIS',
      'MY' => 'DuitNow',
      'PH' => 'GCash',
      'JP' => 'iD / Card',
      'KR' => 'Samsung Pay',
      'BR' => 'Pix',
      _ => 'Card / Wallet',
    };
  }

  String _sampleAmountForCountry(String currencyCode) {
    return switch (currencyCode) {
      'INR' => '240.00',
      'JPY' || 'KRW' => '3,500',
      'VND' || 'IDR' => '65,000',
      'PKR' || 'BDT' => '1,250.00',
      'NGN' || 'KES' => '2,400.00',
      'AED' || 'SAR' || 'QAR' => '85.50',
      'USD' || 'EUR' || 'GBP' || 'CAD' || 'AUD' || 'SGD' || 'NZD' || 'CHF' => '42.50',
      _ => '42.50',
    };
  }

  String _sampleShortAmountForCountry(String currencyCode) {
    return switch (currencyCode) {
      'INR' => '240',
      'JPY' || 'KRW' => '3,500',
      'VND' || 'IDR' => '65K',
      'PKR' || 'BDT' => '1,250',
      'NGN' || 'KES' => '2,400',
      'AED' || 'SAR' || 'QAR' => '85.50',
      'USD' || 'EUR' || 'GBP' || 'CAD' || 'AUD' || 'SGD' || 'NZD' || 'CHF' => '42.50',
      _ => '42.50',
    };
  }

  String _nationalPrideTitle(CountryEntry country) {
    return switch (country.countryCode) {
      'IN' => 'Proudly Tuned for India 🇮🇳',
      'AE' => 'Optimized for UAE 🇦🇪',
      'US' => 'Built for United States 🇺🇸',
      'GB' => 'Tuned for United Kingdom 🇬🇧',
      'SA' => 'Proudly Made for Saudi Arabia 🇸🇦',
      'CA' => 'Tuned for Canada 🇨🇦',
      'AU' => 'Optimized for Australia 🇦🇺',
      'SG' => 'Tuned for Singapore 🇸🇬',
      'PK' => 'Tuned for Pakistan 🇵🇰',
      'BD' => 'Tuned for Bangladesh 🇧🇩',
      'NG' => 'Tuned for Nigeria 🇳🇬',
      'KE' => 'Tuned for Kenya 🇰🇪',
      'DE' => 'Optimized for Germany 🇩🇪',
      'FR' => 'Optimized for France 🇫🇷',
      'JP' => 'Tuned for Japan 🇯🇵',
      'BR' => 'Tuned for Brazil 🇧🇷',
      _ => 'Tuned for ${country.name} ${country.flag}',
    };
  }

  String _nationalPrideSubtitle(CountryEntry country) {
    return switch (country.countryCode) {
      'IN' => 'Auto-detects UPI & 40+ Indian banks in ₹ (INR)',
      'AE' => 'Auto-detects ENBD, ADCB, FAB & cards in AED',
      'US' => 'Auto-detects Chase, BoA, Amex & Apple Pay in \$',
      'GB' => 'Auto-detects Monzo, Barclays, Revolut & cards in £',
      'SA' => 'Auto-detects Al Rajhi, SNB, Riyad & mada in SAR',
      'CA' => 'Auto-detects RBC, TD, Scotiabank & Interac in CA\$',
      'AU' => 'Auto-detects CommBank, ANZ, NAB & cards in A\$',
      'SG' => 'Auto-detects DBS, OCBC, UOB & PayNow in S\$',
      'PK' => 'Auto-detects HBL, Meezan, Raast & JazzCash in Rs',
      'BD' => 'Auto-detects bKash, Nagad & local banks in ৳',
      'NG' => 'Auto-detects GTBank, Access, Zenith & transfers in ₦',
      'KE' => 'Auto-detects M-PESA & Kenyan bank alerts in KSh',
      _ => '100% on-device private tracking in ${country.currencySymbol} (${country.currencyCode})',
    };
  }

  // ─────────────────────────────────────────────────────────────
  // STEP 0 — Dedicated Country & Currency Screen (Keyboard & Landscape Safe)
  // ─────────────────────────────────────────────────────────────

  Widget _buildCountryHeaderTitle({bool isLandscape = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 2, 4, isLandscape ? 2 : 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Where are you based?\nChoose your currency.',
              style: TextStyle(
                fontSize: isLandscape ? 14 : 18,
                fontWeight: FontWeight.w900,
                height: 1.15,
                letterSpacing: -0.5,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 7 : 8,
              vertical: isLandscape ? 3 : 3.5,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _kIncomeOnHero.withValues(alpha: 0.5),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedCountry.flag,
                  style: TextStyle(fontSize: isLandscape ? 12 : 13),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_selectedCountry.currencyCode} (${_selectedCountry.currencySymbol})',
                  style: TextStyle(
                    fontSize: isLandscape ? 11 : 11.5,
                    fontWeight: FontWeight.w800,
                    color: _kIncomeOnHero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNationalPrideCard(String prideTitle, String prideSub,
      {bool isLandscape = false}) {
    return _glass(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 10 : 12,
        vertical: isLandscape ? 6 : 7,
      ),
      radius: isLandscape ? 12 : 13,
      fill: 0.14,
      borderColor: _kIncomeOnHero.withValues(alpha: 0.35),
      child: Row(
        children: [
          Container(
            width: isLandscape ? 30 : 34,
            height: isLandscape ? 30 : 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(
                color: _kIncomeOnHero.withValues(alpha: 0.6),
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _selectedCountry.flag,
              style: TextStyle(fontSize: isLandscape ? 16 : 19),
            ),
          ),
          SizedBox(width: isLandscape ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  prideTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isLandscape ? 12 : 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  prideSub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isLandscape ? 10 : 10.5,
                    fontWeight: FontWeight.w600,
                    color: _kIncomeOnHero.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3.5,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kIncomeOnHero, Color(0xFF00BFA5)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: _kIncomeOnHero.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _selectedCountry.currencySymbol,
              style: TextStyle(
                fontSize: isLandscape ? 11 : 12,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F3632),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountrySearchBar() {
    return GestureDetector(
      onTap: () => _countrySearchFocus.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1.0,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.75),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _countrySearchController,
                focusNode: _countrySearchFocus,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                cursorColor: _kIncomeOnHero,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search 195+ countries or currencies...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.50),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_countrySearchController.text.isNotEmpty)
              GestureDetector(
                onTap: () => _countrySearchController.clear(),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountryChips() {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: CountriesData.popular.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, idx) {
          final item = CountriesData.popular[idx];
          final isSel = item.countryCode == _selectedCountry.countryCode;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _selectCountry(item);
                _countrySearchFocus.unfocus();
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSel
                      ? Colors.white.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSel
                        ? _kIncomeOnHero
                        : Colors.white.withValues(alpha: 0.16),
                    width: isSel ? 1.4 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.flag,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      switch (item.countryCode) {
                        'OTHER' => 'Other',
                        'AE' => 'UAE',
                        'US' => 'USA',
                        'GB' => 'UK',
                        'SA' => 'Saudi',
                        _ => item.name.split(' ').first,
                      },
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSel ? FontWeight.w800 : FontWeight.w600,
                        color: isSel
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCountryListView({bool keyboardOpen = false}) {
    return Container(
      margin: EdgeInsets.only(bottom: keyboardOpen ? 4 : 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _filteredCountries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 28,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'No matching country found',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap "Other" in chips above or check spelling',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(vertical: 2),
              physics: const BouncingScrollPhysics(),
              itemCount: _filteredCountries.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 0.5,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              itemBuilder: (context, i) {
                final c = _filteredCountries[i];
                final isSelected =
                    c.countryCode == _selectedCountry.countryCode;
                return Material(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _selectCountry(c);
                      _countrySearchFocus.unfocus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Text(
                            c.flag,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${c.currencyCode} (${c.currencySymbol})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isSelected
                                        ? _kIncomeOnHero
                                        : Colors.white
                                            .withValues(alpha: 0.65),
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _kIncomeOnHero
                                  : Colors.white
                                      .withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Text(
                              c.currencySymbol,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: isSelected
                                    ? const Color(0xFF0F3632)
                                    : Colors.white,
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 17,
                              color: _kIncomeOnHero,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildCountryBottomAction({bool isLandscape = false}) {
    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: isLandscape ? 4 : 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GradientButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            height: isLandscape ? 46 : 56,
            onTap: () {
              _countrySearchFocus.unfocus();
              _next();
            },
          ),
          SizedBox(height: isLandscape ? 3 : 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: isLandscape ? 11 : 12,
                color: _kIncomeOnHero.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '100% Private • No Bank Login • ${_selectedCountry.currencySymbol}0 Forever',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isLandscape ? 10.5 : 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountrySelectionScreen(bool isDark, {bool isLandscape = false}) {
    final colors = isDark ? _kHeroDark : _kHeroLight;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final prideTitle = _nationalPrideTitle(_selectedCountry);
    final prideSub = _nationalPrideSubtitle(_selectedCountry);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        bottom: true,
        child: isLandscape
            ? Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Left Column: Controls, Title, Pride Card & Continue Action ──
                    Expanded(
                      flex: 5,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight),
                              child: IntrinsicHeight(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildTopBar(isLandscape: true),
                                    const SizedBox(height: 2),
                                    _buildCountryHeaderTitle(isLandscape: true),
                                    const SizedBox(height: 4),
                                    _buildNationalPrideCard(
                                        prideTitle, prideSub,
                                        isLandscape: true),
                                    const Spacer(),
                                    if (!keyboardOpen)
                                      _buildCountryBottomAction(
                                          isLandscape: true),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    // ── Right Column: Search Bar, Chips & Scrollable List ──
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 2),
                          _buildCountrySearchBar(),
                          const SizedBox(height: 4),
                          _buildCountryChips(),
                          const SizedBox(height: 4),
                          Expanded(
                            child: _buildCountryListView(
                                keyboardOpen: keyboardOpen),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBar(),
                    const SizedBox(height: 2),
                    _buildCountryHeaderTitle(),
                    _buildNationalPrideCard(prideTitle, prideSub),
                    const SizedBox(height: 5),
                    _buildCountrySearchBar(),
                    const SizedBox(height: 4),
                    _buildCountryChips(),
                    const SizedBox(height: 6),
                    Expanded(
                      child:
                          _buildCountryListView(keyboardOpen: keyboardOpen),
                    ),
                    if (!keyboardOpen) ...[
                      _buildCountryBottomAction(),
                    ],
                  ],
                ),
              ),
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
  final double height;
  final Key? labelKey;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.glow = 0.30,
    this.height = 56,
    this.labelKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
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
                          style: TextStyle(
                            fontSize: height < 50 ? 15 : 16.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(icon, size: height < 50 ? 18 : 20, color: Colors.white),
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
// Swiggy Logo Painter (official brand logo vector)
// ─────────────────────────────────────────────────────────────
class _SwiggyLogoPainter extends CustomPainter {
  final Color color;
  const _SwiggyLogoPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // ViewBox is 24x24
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final path = Path();
    path.moveTo(12.034, 24.0);
    path.relativeCubicTo(-0.376, -0.411, -2.075, -2.584, -3.95, -5.513);
    path.relativeCubicTo(-0.547, -0.916, -0.901, -1.63, -0.833, -1.814);
    path.relativeCubicTo(0.178, -0.48, 3.355, -0.743, 4.333, -0.308);
    path.relativeCubicTo(0.298, 0.132, 0.29, 0.307, 0.29, 0.409);
    path.relativeCubicTo(0.0, 0.44, -0.022, 1.619, -0.022, 1.619);
    path.relativeArcToPoint(
      const Offset(0.883, -0.002),
      radius: const Radius.elliptical(0.441, 0.441),
      rotation: 0.0,
      largeArc: true,
      clockwise: false,
    );
    path.relativeLineTo(-0.005, -2.939);
    path.relativeCubicTo(0.0, -0.255, -0.278, -0.319, -0.331, -0.329);
    path.relativeCubicTo(-0.511, -0.002, -1.548, -0.006, -2.661, -0.006);
    path.relativeCubicTo(-2.457, 0.0, -3.006, 0.101, -3.423, -0.172);
    path.relativeCubicTo(-0.904, -0.591, -2.383, -4.577, -2.417, -6.819);
    path.cubicTo(3.849, 4.964, 5.723, 2.225, 8.362, 0.868);
    path.arcToPoint(
      const Offset(12.026, 0.0),
      radius: const Radius.elliptical(8.13, 8.13),
      rotation: 0.0,
      largeArc: false,
      clockwise: true,
    );
    path.relativeCubicTo(4.177, 0.0, 7.617, 3.153, 8.075, 7.209);
    path.relativeLineTo(0.001, 0.011);
    path.relativeCubicTo(0.084, 0.981, -5.321, 1.189, -6.39, 0.904);
    path.relativeCubicTo(-0.164, -0.044, -0.206, -0.212, -0.206, -0.284);
    path.lineTo(13.5, 4.996);
    path.relativeArcToPoint(
      const Offset(-0.884, 0.002),
      radius: const Radius.elliptical(0.442, 0.442),
      rotation: 0.0,
      largeArc: false,
      clockwise: false,
    );
    path.relativeLineTo(0.009, 3.866);
    path.relativeArcToPoint(
      const Offset(0.268, 0.32),
      radius: const Radius.elliptical(0.33, 0.33),
      rotation: 0.0,
      largeArc: false,
      clockwise: false,
    );
    path.relativeLineTo(3.354, -0.001);
    path.relativeCubicTo(1.79, 0.0, 2.542, 0.207, 3.042, 0.588);
    path.relativeCubicTo(0.333, 0.254, 0.461, 0.739, 0.349, 1.37);
    path.cubicTo(18.633, 16.755, 12.273, 23.71, 12.034, 24.0);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SwiggyLogoPainter old) => old.color != color;
}
