import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/home_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/statistics_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/borrow_lend_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/profile_screen.dart';
import 'package:buddy/views/screens/add_transaction_screen.dart';
import 'package:buddy/services/app_init_helper.dart';
import 'package:buddy/services/support_service.dart';
import 'package:buddy/views/widgets/offline_banner.dart';

class BottomNavbarScreen extends StatefulWidget {
  const BottomNavbarScreen({super.key});

  @override
  State<BottomNavbarScreen> createState() => BottomNavbarScreenState();
}

class BottomNavbarScreenState extends State<BottomNavbarScreen>
    with SingleTickerProviderStateMixin {
  void switchTab(int index) => _goTo(index);

  late final PageController _pageController;
  int _currentIndex = 0;
  int _lastHapticTab = 0;
  double _dragStartPage = 0;
  double _dragAccumX = 0;
  Widget? _homePage;
  Widget? _statsPage;
  Widget? _debtsPage;
  Widget? _profilePage;

  Widget _getPage(int index) {
    switch (index) {
      case 0:
        return _homePage ??= HomeScreen(key: _homeKey);
      case 1:
        return _statsPage ??= StatisticsScreen(key: _statisticsKey);
      case 2:
        return _debtsPage ??= BorrowLendScreen(key: _borrowLendKey);
      case 3:
        return _profilePage ??= ProfileScreen(key: _profileKey);
      default:
        return const SizedBox.shrink();
    }
  }

  late final AnimationController _fabController;
  late final Animation<double> _fabBob;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<StatisticsScreenState> _statisticsKey =
      GlobalKey<StatisticsScreenState>();
  final GlobalKey<BorrowLendScreenState> _borrowLendKey =
      GlobalKey<BorrowLendScreenState>();
  final GlobalKey<ProfileScreenState> _profileKey =
      GlobalKey<ProfileScreenState>();

  static const _navItems = [
    _NavItemData(
      icon: Icons.home_rounded,
      outline: Icons.home_outlined,
      label: 'Home',
    ),
    _NavItemData(
      icon: Icons.bar_chart_rounded,
      outline: Icons.bar_chart_outlined,
      label: 'Stats',
    ),
    _NavItemData(
      icon: Icons.handshake_rounded,
      outline: Icons.handshake_outlined,
      label: 'Debts',
    ),
    _NavItemData(
      icon: Icons.person_rounded,
      outline: Icons.person_outline_rounded,
      label: 'Profile',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _fabBob = Tween<double>(
      begin: -6.0,
      end: 6.0,
    ).animate(CurvedAnimation(parent: _fabController, curve: Curves.easeInOut));
    _fabController.repeat(reverse: true);

    // Defer non-critical background maintenance until AFTER initial rendering is complete & idle
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        AppInitHelper.initialize();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        SupportService.checkAndShowMonthlySupportPrompt(context);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final bottomSafe = mq.padding.bottom;

    // ── Responsive scaling factors ──
    // Base design: 390pt wide (iPhone 14). Scale relative to that.
    final double sw = screenW / 390.0;
    final double sh = screenH / 844.0;
    // Clamp scale so nothing gets absurdly large on tablets or tiny on SE
    final double s = sw.clamp(0.8, 1.3);

    final isDark = AppColors.isDark(context);
    final double navBarH = (52 * s).clamp(44.0, 64.0);
    const double navRadius = 100.0; // Clean capsule pill shape
    final double hPad = (16 * s).clamp(12.0, 24.0);
    final double vPad = (6 * s).clamp(4.0, 10.0);
    final double iconSize = (22 * s).clamp(18.0, 26.0);
    final double labelSize = (13 * s).clamp(11.0, 15.0);
    const double pillRadius = 100.0; // Clean capsule pill shape, not squircle

    // FAB sizing (Floating Lottie Action Button)
    final double fabSize = (78 * s).clamp(70.0, 94.0);
    final double fabBottom = (108 * sh).clamp(88.0, 138.0);
    final double fabRight = (18 * s).clamp(12.0, 26.0);
    final double fabIconSize = (28 * s).clamp(22.0, 34.0);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      backgroundColor: AppColors.backgroundOf(context),
      body: Stack(
        children: [
          RepaintBoundary(
            child: PageView.builder(
              controller: _pageController,
              itemCount: 4,
              physics: const PageScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              onPageChanged: (i) {
                _currentIndex = i;
              },
              itemBuilder: (context, index) {
                return _getPage(index);
              },
            ),
          ),

          // Global offline status indicator banner
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OfflineBanner(),
          ),

          // Glassmorphic bottom bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RepaintBoundary(
              child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, math.max(bottomSafe > 0 ? 0 : 6, 6 * s)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(navRadius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: isDark
                              ? [
                                  const Color(0xFF0F2624).withValues(alpha: 0.90),
                                  const Color(0xFF081615).withValues(alpha: 0.96),
                                ]
                              : [
                                  const Color(0xFF0A2421).withValues(alpha: 0.94),
                                  const Color(0xFF113834).withValues(alpha: 0.98),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(navRadius),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.20 : 0.35,
                          ),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.45 : 0.24,
                            ),
                            blurRadius: 28,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: const Color(0xFF0F3632).withValues(
                              alpha: isDark ? 0.25 : 0.22,
                            ),
                            blurRadius: 16,
                            offset: const Offset(0, 2),
                          ),
                          if (!isDark)
                            BoxShadow(
                              color: const Color(0xFF38B2A6).withValues(alpha: 0.14),
                              blurRadius: 8,
                              offset: const Offset(0, -1),
                            ),
                        ],
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: vPad,
                        vertical: vPad,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final totalWidth = constraints.maxWidth;
                          const itemCount = 4;
                          final itemWidth = totalWidth / itemCount;
                          const double pillInset = 2.5;
                          final double pillWidth = itemWidth - 2 * pillInset;

                          return AnimatedBuilder(
                            animation: _pageController,
                            builder: (context, _) {
                              final double currentPage = _pageController.hasClients &&
                                      _pageController.position.haveDimensions
                                  ? (_pageController.page ?? _currentIndex.toDouble())
                                  : _currentIndex.toDouble();

                              final int selectedIndex = currentPage.round().clamp(0, 3);
                              if (selectedIndex != _lastHapticTab) {
                                _lastHapticTab = selectedIndex;
                                HapticFeedback.selectionClick();
                              }

                              // Organic liquid stretch as slider glides between tabs
                              final double stretch = (1.0 - 2.0 * (currentPage - currentPage.floor() - 0.5).abs()).clamp(0.0, 1.0) * (5.0 * s);
                              final double activePillWidth = pillWidth + stretch;
                              final double activeLeftOffset = (currentPage * itemWidth + pillInset - stretch / 2.0)
                                  .clamp(pillInset, totalWidth - activePillWidth - pillInset);

                              return GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onPanStart: (details) {
                                  _dragAccumX = 0;
                                  _dragStartPage = currentPage;
                                  _lastHapticTab = currentPage.round().clamp(0, 3);
                                  HapticFeedback.lightImpact();
                                },
                                onPanUpdate: (details) {
                                  _dragAccumX += details.delta.dx;
                                  final deltaPages = _dragAccumX / itemWidth;
                                  final double newPage =
                                      (_dragStartPage + deltaPages).clamp(
                                    0.0,
                                    (itemCount - 1).toDouble(),
                                  );
                                  if (_pageController.hasClients &&
                                      _pageController.position.haveDimensions) {
                                    final w = _pageController
                                        .position.viewportDimension;
                                    _pageController.position.jumpTo(newPage * w);
                                  }
                                  final int nearest = newPage.round().clamp(0, 3);
                                  if (nearest != _lastHapticTab) {
                                    _lastHapticTab = nearest;
                                    HapticFeedback.selectionClick();
                                  }
                                },
                                onPanEnd: (details) {
                                  final target =
                                      (_pageController.page ?? currentPage).round().clamp(0, 3);
                                  _goTo(target);
                                },
                                child: SizedBox(
                                  height: navBarH,
                                  child: Stack(
                                    children: [
                                      // ── Seamless Physical Sliding Pill (glides smoothly across tabs) ──
                                      Positioned(
                                        left: activeLeftOffset,
                                        width: activePillWidth,
                                        top: 2,
                                        bottom: 2,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(pillRadius),
                                            gradient: isDark
                                                ? const LinearGradient(
                                                    colors: [
                                                      Color(0xFF287A70),
                                                      Color(0xFF1B554E),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  )
                                                : const LinearGradient(
                                                    colors: [
                                                      Color(0xFF38B2A6),
                                                      Color(0xFF228277),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: isDark ? 0.35 : 0.70,
                                              ),
                                              width: 1.2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: isDark
                                                    ? const Color(0xFF1E5D57).withValues(alpha: 0.40)
                                                    : const Color(0xFF38B2A6).withValues(alpha: 0.55),
                                                blurRadius: isDark ? 12 : 14,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // ── Tab items row (positioned over the sliding pill) ──
                                      Row(
                                        children: List.generate(itemCount, (i) {
                                          final double dist = (currentPage - i).abs();
                                          final double rawFactor = (1.0 - (dist / 0.75)).clamp(0.0, 1.0);
                                          final double growFactor = Curves.easeInOutCubic.transform(rawFactor);
                                          final bool isSelected = selectedIndex == i;

                                          return Expanded(
                                            child: GestureDetector(
                                              onTap: () => _goTo(i),
                                              behavior: HitTestBehavior.opaque,
                                              child: Center(
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Transform.scale(
                                                      scale: 1.0 + (growFactor * 0.10),
                                                      child: Icon(
                                                        isSelected
                                                            ? _navItems[i].icon
                                                            : _navItems[i].outline,
                                                        size: iconSize,
                                                        color: Color.lerp(
                                                          Colors.white.withValues(alpha: isDark ? 0.55 : 0.70),
                                                          Colors.white,
                                                          growFactor,
                                                        ),
                                                      ),
                                                    ),
                                                    ClipRect(
                                                      child: Align(
                                                        alignment: Alignment.centerLeft,
                                                        widthFactor: growFactor,
                                                        child: Padding(
                                                          padding: EdgeInsets.only(left: 4.5 * s),
                                                          child: Text(
                                                            _navItems[i].label,
                                                            style: TextStyle(
                                                              color: Colors.white.withValues(
                                                                alpha: growFactor.clamp(0.0, 1.0),
                                                              ),
                                                              fontSize: labelSize,
                                                              fontWeight: FontWeight.w800,
                                                              letterSpacing: -0.2,
                                                            ),
                                                            maxLines: 1,
                                                            softWrap: false,
                                                            overflow: TextOverflow.clip,
                                                          ),
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
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

          // Animated themed Liquid Glass FAB above navbar (rendered last to be on top)
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.only(bottom: fabBottom, right: fabRight),
                child: AnimatedBuilder(
                  animation: _fabBob,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _fabBob.value),
                    child: child,
                  ),
                  child: RepaintBoundary(
                    child: _LiquidGlassFab(
                      size: fabSize,
                      iconSize: fabIconSize,
                      isDark: isDark,
                      onTap: () => _openAddTransactionSheet(context),
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

  void _goTo(int index) {
    if (!_pageController.hasClients) return;
    final double curP = _pageController.hasClients &&
            _pageController.position.haveDimensions
        ? (_pageController.page ?? _currentIndex.toDouble())
        : _currentIndex.toDouble();
    if (index == _currentIndex && curP.round() == index) {
      HapticFeedback.selectionClick();
      return;
    }

    final int distance = (index - curP.round()).abs().clamp(1, 3);
    _currentIndex = index;
    HapticFeedback.lightImpact();

    // Smoothly animate across any distance with natural timing
    final int durationMs = 260 + (distance - 1) * 70;
    _pageController.animateToPage(
      index,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.easeInOutCubic,
    ).then((_) {
      if (mounted) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  Future<void> _openAddTransactionSheet(BuildContext context) async {
    HapticFeedback.mediumImpact();
    // On Borrow/Lend tab: delegate to that screen — it
    // will pre-select Lend or Borrow based on active filter
    if (_currentIndex == 2) {
      _borrowLendKey.currentState?.openAddSheet();
      return;
    }

    // All other tabs: open the add transaction sheet
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
            child: Material(
              color: AppColors.backgroundOf(ctx),
              child: const AddTransactionScreen(),
            ),
          ),
        );
      },
    );

    // Refresh all screens if transaction was added
    if (result == true && mounted) {
      debugPrint('💾 Transaction saved, refreshing all screens...');
      final homeState = _homeKey.currentState;
      final statisticsState = _statisticsKey.currentState;
      final borrowLendState = _borrowLendKey.currentState;
      final profileState = _profileKey.currentState;

      debugPrint('Home state: ${homeState != null ? "Found ✓" : "NULL ✗"}');
      debugPrint('Statistics state: ${statisticsState != null ? "Found ✓" : "NULL ✗"}');
      debugPrint('BorrowLend state: ${borrowLendState != null ? "Found ✓" : "NULL ✗"}');
      debugPrint('Profile state: ${profileState != null ? "Found ✓" : "NULL ✗"}');

      if (homeState != null) {
        await homeState.refreshData();
      }
      if (statisticsState != null) {
        await statisticsState.refreshData();
      }
      if (borrowLendState != null) {
        await borrowLendState.refreshData();
      }
      if (profileState != null) {
        profileState.refreshData();
      }

      debugPrint('✅ All screens refresh triggered');
    }
  }
}

/// Authentic iOS Liquid Glass circular Floating Action Button
class _LiquidGlassFab extends StatefulWidget {
  final double size;
  final double iconSize;
  final bool isDark;
  final VoidCallback onTap;

  const _LiquidGlassFab({
    required this.size,
    required this.iconSize,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_LiquidGlassFab> createState() => _LiquidGlassFabState();
}

class _LiquidGlassFabState extends State<_LiquidGlassFab> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final size = widget.size;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Animated Money Lottie (freely floating without background container)
              Transform.scale(
                scale: 1.15,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Lottie.asset(
                    'assets/lottie/jsonlottie/Moneylottie.json',
                    fit: BoxFit.contain,
                    repeat: true,
                  ),
                ),
              ),
              // '+' symbol badge with the signature emerald pill gradient & glow
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isDark
                        ? const LinearGradient(
                            colors: [
                              Color(0xFF287A70),
                              Color(0xFF1B554E),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [
                              Color(0xFF38B2A6),
                              Color(0xFF228277),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.40 : 0.75,
                      ),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? const Color(0xFF1E5D57).withValues(alpha: 0.50)
                            : const Color(0xFF38B2A6).withValues(alpha: 0.60),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.35 : 0.20,
                        ),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData outline;
  final String label;
  const _NavItemData({required this.icon, required this.outline, required this.label});
}
