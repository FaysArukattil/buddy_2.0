import 'package:flutter/material.dart';
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
  void switchTab(int index) {
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  late final PageController _pageController;
  int _currentIndex = 0;
  double _dragStartPage = 0;
  double _dragAccumX = 0;
  late final List<Widget> _pages;
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
    _NavItemData(icon: Icons.home_rounded, outline: Icons.home_outlined, label: 'Home'),
    _NavItemData(icon: Icons.bar_chart_rounded, outline: Icons.bar_chart_rounded, label: 'Stats'),
    _NavItemData(icon: Icons.handshake_rounded, outline: Icons.handshake_outlined, label: 'Debts'),
    _NavItemData(icon: Icons.person_rounded, outline: Icons.person_outline_rounded, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    AppInitHelper.initialize();
    AppInitHelper.seedCategoriesIfNeeded();
    _pageController = PageController(initialPage: _currentIndex);
    _pages = [
      HomeScreen(key: _homeKey),
      StatisticsScreen(key: _statisticsKey),
      BorrowLendScreen(key: _borrowLendKey),
      ProfileScreen(key: _profileKey),
    ];
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _fabBob = Tween<double>(
      begin: -6.0,
      end: 6.0,
    ).animate(CurvedAnimation(parent: _fabController, curve: Curves.easeInOut));
    _fabController.repeat(reverse: true);

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

    final double navBarH = (52 * s).clamp(44.0, 64.0);
    final double navRadius = (28 * s).clamp(22.0, 36.0);
    final double hPad = (16 * s).clamp(12.0, 24.0);
    final double vPad = (6 * s).clamp(4.0, 10.0);
    final double iconSize = (22 * s).clamp(18.0, 26.0);
    final double labelSize = (13 * s).clamp(11.0, 15.0);
    final double pillRadius = (18 * s).clamp(14.0, 22.0);

    // FAB sizing
    final double fabSize = (60 * s).clamp(50.0, 72.0);
    final double fabRadius = (20 * s).clamp(16.0, 26.0);
    final double fabBottom = (110 * sh).clamp(90.0, 140.0);
    final double fabRight = (20 * s).clamp(14.0, 28.0);
    final double fabIconSize = (28 * s).clamp(22.0, 34.0);

    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.backgroundOf(context),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const PageScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            onPageChanged: (i) {
              _currentIndex = i;
            },
            children: _pages,
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
                          colors: AppColors.isDark(context)
                              ? [
                                  const Color(0xFF0F2624).withValues(alpha: 0.90),
                                  const Color(0xFF081615).withValues(alpha: 0.96),
                                ]
                              : [
                                  const Color(0xFF0F3632).withValues(alpha: 0.92),
                                  const Color(0xFF14423E).withValues(alpha: 0.96),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(navRadius),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: AppColors.isDark(context) ? 0.18 : 0.24,
                          ),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: AppColors.isDark(context) ? 0.45 : 0.08,
                            ),
                            blurRadius: 28,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: const Color(0xFF1E5D57).withValues(
                              alpha: AppColors.isDark(context) ? 0.25 : 0.10,
                            ),
                            blurRadius: 16,
                            offset: const Offset(0, -1),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: vPad,
                        vertical: vPad,
                      ),
                      child: AnimatedBuilder(
                        animation: _pageController,
                        builder: (context, _) {
                          final double currentPage = _pageController.hasClients &&
                                  _pageController.position.haveDimensions
                              ? (_pageController.page ?? _currentIndex.toDouble())
                              : _currentIndex.toDouble();

                          final int selectedIndex = currentPage.round().clamp(0, 3);

                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final totalWidth = constraints.maxWidth;
                              const itemCount = 4;
                              final itemWidth = totalWidth / itemCount;
                              const double pillInset = 2.5;
                              final double pillWidth = itemWidth - 2 * pillInset;
                              final double leftOffset = (currentPage * itemWidth + pillInset)
                                  .clamp(pillInset, totalWidth - itemWidth + pillInset);

                              return GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onPanStart: (details) {
                                  _dragAccumX = 0;
                                  _dragStartPage = currentPage;
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
                                },
                                onPanEnd: (details) {
                                  final target =
                                      (_pageController.page ?? currentPage).round();
                                  _goTo(target);
                                },
                                child: SizedBox(
                                  height: navBarH,
                                  child: Stack(
                                    children: [
                                      // ── Seamless Physical Sliding Pill (glides smoothly across tabs) ──
                                      Positioned(
                                        left: leftOffset,
                                        width: pillWidth,
                                        top: 2,
                                        bottom: 2,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(pillRadius),
                                            gradient: AppColors.isDark(context)
                                                ? const LinearGradient(
                                                    colors: [
                                                      Color(0xFF26736A),
                                                      Color(0xFF1B534D),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  )
                                                : const LinearGradient(
                                                    colors: [
                                                      Color(0xFF236C64),
                                                      Color(0xFF194F48),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: AppColors.isDark(context) ? 0.35 : 0.40,
                                              ),
                                              width: 1.0,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF1E5D57).withValues(
                                                  alpha: AppColors.isDark(context) ? 0.40 : 0.28,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 3),
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
                                                    Icon(
                                                      isSelected
                                                          ? _navItems[i].icon
                                                          : _navItems[i].outline,
                                                      size: iconSize,
                                                      color: Color.lerp(
                                                        Colors.white.withValues(alpha: 0.50),
                                                        Colors.white,
                                                        growFactor,
                                                      ),
                                                    ),
                                                    ClipRect(
                                                      child: Align(
                                                        alignment: Alignment.centerLeft,
                                                        widthFactor: growFactor,
                                                        child: Opacity(
                                                          opacity: growFactor,
                                                          child: Padding(
                                                            padding: EdgeInsets.only(left: 4.5 * s),
                                                            child: Text(
                                                              _navItems[i].label,
                                                              style: TextStyle(
                                                                color: Colors.white,
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

          // Animated themed FAB above navbar (rendered last to be on top)
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
                  child: GestureDetector(
                    onTap: () async {
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
                        debugPrint(
                          '💾 Transaction saved, refreshing all screens...',
                        );
                        final homeState = _homeKey.currentState;
                        final statisticsState = _statisticsKey.currentState;
                        final borrowLendState = _borrowLendKey.currentState;
                        final profileState = _profileKey.currentState;

                        debugPrint(
                          'Home state: ${homeState != null ? "Found ✓" : "NULL ✗"}',
                        );
                        debugPrint(
                          'Statistics state: ${statisticsState != null ? "Found ✓" : "NULL ✗"}',
                        );
                        debugPrint(
                          'BorrowLend state: ${borrowLendState != null ? "Found ✓" : "NULL ✗"}',
                        );
                        debugPrint(
                          'Profile state: ${profileState != null ? "Found ✓" : "NULL ✗"}',
                        );

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
                    },
                    child: Container(
                      width: fabSize,
                      height: fabSize,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.secondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(fabRadius),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(Icons.add_rounded, size: fabIconSize, color: Colors.white),
                      ),
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
    if (index == _currentIndex &&
        _pageController.hasClients &&
        _pageController.page?.round() == index) {
      return;
    }
    _currentIndex = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData outline;
  final String label;
  const _NavItemData({required this.icon, required this.outline, required this.label});
}
