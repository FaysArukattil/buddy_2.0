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
  bool _isDraggingNavbar = false;
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
      icon: Icons.receipt_long_rounded,
      outline: Icons.receipt_long_outlined,
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

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: (details) {
                              _isDraggingNavbar = true;
                              _dragAccumX = 0;
                              final curP = _pageController.hasClients &&
                                      _pageController.position.haveDimensions
                                  ? (_pageController.page ?? _currentIndex.toDouble())
                                  : _currentIndex.toDouble();
                              _dragStartPage = curP;
                              _lastHapticTab = curP.round().clamp(0, 3);
                              HapticFeedback.lightImpact();
                            },
                            onHorizontalDragUpdate: (details) {
                              _dragAccumX += details.delta.dx;
                              final deltaPages = _dragAccumX / itemWidth;
                              final double newPage =
                                  (_dragStartPage + deltaPages).clamp(0.0, 3.0);
                              if (_pageController.hasClients &&
                                  _pageController.position.haveDimensions) {
                                final w = _pageController
                                    .position.viewportDimension;
                                _pageController.position.jumpTo(newPage * w);
                              }
                              final int currentStop = newPage.round().clamp(0, 3);
                              if (currentStop != _lastHapticTab) {
                                _lastHapticTab = currentStop;
                                HapticFeedback.lightImpact();
                              }
                            },
                            onHorizontalDragEnd: (details) {
                              _isDraggingNavbar = false;
                              final curP = _pageController.hasClients &&
                                      _pageController.position.haveDimensions
                                  ? (_pageController.page ?? _currentIndex.toDouble())
                                  : _currentIndex.toDouble();
                              final v = details.primaryVelocity ?? 0;
                              int target = curP.round().clamp(0, 3);
                              if (v > 200) {
                                target = (curP.floor() + 1).clamp(0, 3);
                              } else if (v < -200) {
                                target = (curP.ceil() - 1).clamp(0, 3);
                              }
                              _goTo(target);
                            },
                            onHorizontalDragCancel: () {
                              _isDraggingNavbar = false;
                              final curP = _pageController.hasClients &&
                                      _pageController.position.haveDimensions
                                  ? (_pageController.page ?? _currentIndex.toDouble())
                                  : _currentIndex.toDouble();
                              _goTo(curP.round().clamp(0, 3));
                            },
                            child: AnimatedBuilder(
                              animation: _pageController,
                              builder: (context, _) {
                                final double currentPage = _pageController.hasClients &&
                                        _pageController.position.haveDimensions
                                    ? (_pageController.page ?? _currentIndex.toDouble())
                                    : _currentIndex.toDouble();

                                final int selectedIndex = currentPage.round().clamp(0, 3);
                                if (!_isDraggingNavbar && selectedIndex != _lastHapticTab) {
                                  _lastHapticTab = selectedIndex;
                                  HapticFeedback.lightImpact();
                                }

                                // Organic liquid stretch as slider glides between tabs
                                final double stretch = (1.0 - 2.0 * (currentPage - currentPage.floor() - 0.5).abs()).clamp(0.0, 1.0) * (5.0 * s);
                                final double activePillWidth = pillWidth + stretch;
                                final double activeLeftOffset = (currentPage * itemWidth + pillInset - stretch / 2.0)
                                    .clamp(pillInset, totalWidth - activePillWidth - pillInset);

                                return SizedBox(
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
                                          final double rawFactor = (1.0 - (dist / 0.70)).clamp(0.0, 1.0);
                                          final double growFactor = Curves.easeInOutCubic.transform(rawFactor);

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
                                                      child: _buildNavItemIcon(
                                                        i,
                                                        growFactor,
                                                        iconSize,
                                                        isDark,
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
                                );
                              },
                            ),
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

  Widget _buildNavItemIcon(int i, double growFactor, double iconSize, bool isDark) {
    final outlineColor = Colors.white.withValues(alpha: isDark ? 0.60 : 0.75);
    const fillColor = Colors.white;

    if (i == 1) {
      // Stats: Custom vector bar chart with true hollow outline when unselected & solid fill when selected
      return _BarChartNavIcon(
        growFactor: growFactor,
        size: iconSize,
        outlineColor: outlineColor,
        fillColor: fillColor,
      );
    } else if (i == 2) {
      // Debts: Custom vector zigzag receipt with true hollow outline when unselected & solid white filled sheet when selected
      final cutoutColor = isDark ? const Color(0xFF1B554E) : const Color(0xFF228277);
      return _ReceiptNavIcon(
        growFactor: growFactor,
        size: iconSize,
        outlineColor: outlineColor,
        fillColor: fillColor,
        cutoutColor: cutoutColor,
      );
    } else {
      // Home (0) and Profile (3): Material icons with genuine outline/filled pairs
      return Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: (1.0 - growFactor).clamp(0.0, 1.0),
            child: Icon(
              _navItems[i].outline,
              size: iconSize,
              color: outlineColor,
            ),
          ),
          Opacity(
            opacity: growFactor.clamp(0.0, 1.0),
            child: Icon(
              _navItems[i].icon,
              size: iconSize,
              color: fillColor,
            ),
          ),
        ],
      );
    }
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

class _BarChartNavIcon extends StatelessWidget {
  final double growFactor;
  final double size;
  final Color outlineColor;
  final Color fillColor;

  const _BarChartNavIcon({
    required this.growFactor,
    required this.size,
    required this.outlineColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BarChartPainter(
          growFactor: growFactor,
          outlineColor: outlineColor,
          fillColor: fillColor,
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final double growFactor;
  final Color outlineColor;
  final Color fillColor;

  _BarChartPainter({
    required this.growFactor,
    required this.outlineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    final rrects = [
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3.2 * s, 11.5 * s, 4.6 * s, 9.5 * s),
        Radius.circular(1.6 * s),
      ),
      RRect.fromRectAndRadius(
        Rect.fromLTWH(9.7 * s, 3.5 * s, 4.6 * s, 17.5 * s),
        Radius.circular(1.6 * s),
      ),
      RRect.fromRectAndRadius(
        Rect.fromLTWH(16.2 * s, 7.5 * s, 4.6 * s, 13.5 * s),
        Radius.circular(1.6 * s),
      ),
    ];

    // 1. Draw outline if not fully selected
    if (growFactor < 1.0) {
      final outlinePaint = Paint()
        ..color = outlineColor.withValues(alpha: (1.0 - growFactor) * outlineColor.a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35 * s;
      for (final rrect in rrects) {
        canvas.drawRRect(rrect, outlinePaint);
      }
    }

    // 2. Draw solid fill when selected
    if (growFactor > 0.0) {
      final fillPaint = Paint()
        ..color = fillColor.withValues(alpha: growFactor * fillColor.a)
        ..style = PaintingStyle.fill;
      for (final rrect in rrects) {
        canvas.drawRRect(rrect, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.growFactor != growFactor ||
      oldDelegate.outlineColor != outlineColor ||
      oldDelegate.fillColor != fillColor;
}

class _ReceiptNavIcon extends StatelessWidget {
  final double growFactor;
  final double size;
  final Color outlineColor;
  final Color fillColor;
  final Color cutoutColor;

  const _ReceiptNavIcon({
    required this.growFactor,
    required this.size,
    required this.outlineColor,
    required this.fillColor,
    required this.cutoutColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ReceiptPainter(
          growFactor: growFactor,
          outlineColor: outlineColor,
          fillColor: fillColor,
          cutoutColor: cutoutColor,
        ),
      ),
    );
  }
}

class _ReceiptPainter extends CustomPainter {
  final double growFactor;
  final Color outlineColor;
  final Color fillColor;
  final Color cutoutColor;

  _ReceiptPainter({
    required this.growFactor,
    required this.outlineColor,
    required this.fillColor,
    required this.cutoutColor,
  });

  Path _buildReceiptPath(double s) {
    final path = Path();
    final left = 4.8 * s;
    final right = 19.2 * s;
    final top = 2.5 * s;
    final r = 2.2 * s;
    final bottomValley = 19.5 * s;
    final bottomPeak = 21.8 * s;

    // Top-left corner
    path.moveTo(left, top + r);
    path.arcToPoint(Offset(left + r, top), radius: Radius.circular(r));
    // Top edge
    path.lineTo(right - r, top);
    // Top-right corner
    path.arcToPoint(Offset(right, top + r), radius: Radius.circular(r));
    // Right edge down
    path.lineTo(right, bottomValley);

    // Zigzag serrated bottom (3 teeth)
    final toothW = (right - left) / 3.0;
    for (int i = 0; i < 3; i++) {
      final xStart = right - (i * toothW);
      final xMid = xStart - (toothW / 2.0);
      final xEnd = xStart - toothW;
      path.lineTo(xMid, bottomPeak);
      path.lineTo(xEnd, bottomValley);
    }

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    final receiptPath = _buildReceiptPath(s);

    // 1. Draw outline when unselected
    if (growFactor < 1.0) {
      final outlinePaint = Paint()
        ..color = outlineColor.withValues(alpha: (1.0 - growFactor) * outlineColor.a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35 * s
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(receiptPath, outlinePaint);

      // Draw interior lines in outline
      final linePaint = Paint()
        ..color = outlineColor.withValues(alpha: (1.0 - growFactor) * outlineColor.a)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.25 * s;

      canvas.drawLine(Offset(8.0 * s, 7.5 * s), Offset(16.0 * s, 7.5 * s), linePaint);
      canvas.drawLine(Offset(8.0 * s, 11.5 * s), Offset(16.0 * s, 11.5 * s), linePaint);
      canvas.drawLine(Offset(8.0 * s, 15.5 * s), Offset(13.0 * s, 15.5 * s), linePaint);
    }

    // 2. Draw solid fill when selected
    if (growFactor > 0.0) {
      final fillPaint = Paint()
        ..color = fillColor.withValues(alpha: growFactor * fillColor.a)
        ..style = PaintingStyle.fill;
      canvas.drawPath(receiptPath, fillPaint);

      // Slit cutouts in the solid receipt
      final slitPaint = Paint()
        ..color = cutoutColor.withValues(alpha: growFactor * cutoutColor.a)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.4 * s;

      canvas.drawLine(Offset(8.0 * s, 7.5 * s), Offset(16.0 * s, 7.5 * s), slitPaint);
      canvas.drawLine(Offset(8.0 * s, 11.5 * s), Offset(16.0 * s, 11.5 * s), slitPaint);
      canvas.drawLine(Offset(8.0 * s, 15.5 * s), Offset(13.0 * s, 15.5 * s), slitPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReceiptPainter oldDelegate) =>
      oldDelegate.growFactor != growFactor ||
      oldDelegate.outlineColor != outlineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.cutoutColor != cutoutColor;
}
