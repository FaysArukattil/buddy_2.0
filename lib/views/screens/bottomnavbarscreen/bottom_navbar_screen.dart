import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/home_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/statistics_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/profile_screen.dart';
import 'package:buddy/views/screens/add_transaction_screen.dart';

class BottomNavbarScreen extends StatefulWidget {
  const BottomNavbarScreen({super.key});

  @override
  State<BottomNavbarScreen> createState() => _BottomNavbarScreenState();
}

class _BottomNavbarScreenState extends State<BottomNavbarScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  int _currentIndex = 0;
  double _page = 0;
  bool _dragging = false;
  double _dragIndicatorPage = 0;
  double _dragStartPage = 0;
  double _dragAccumX = 0;
  late final AnimationController _fabController;
  late final Animation<double> _fabBob;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<StatisticsScreenState> _statisticsKey =
      GlobalKey<StatisticsScreenState>();
  final GlobalKey<ProfileScreenState> _profileKey =
      GlobalKey<ProfileScreenState>();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _pageController.addListener(() {
      final p = _pageController.page ?? _currentIndex.toDouble();
      if (p != _page) setState(() => _page = p);
    });
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _fabBob = Tween<double>(
      begin: -6.0,
      end: 6.0,
    ).animate(CurvedAnimation(parent: _fabController, curve: Curves.easeInOut));
    _fabController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              // Refresh statistics screen when navigating to it
              if (i == 1) {
                _statisticsKey.currentState?.refreshData();
              }
            },
            children: [
              HomeScreen(key: _homeKey),
              StatisticsScreen(key: _statisticsKey),
              ProfileScreen(key: _profileKey),
            ],
          ),

          // Glassmorphic bottom bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        border: Border.all(
                          color: AppColors.secondary.withValues(alpha: 0.24),
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 20,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final totalWidth = constraints.maxWidth;
                          const itemCount = 3;
                          final itemWidth = totalWidth / itemCount;
                          final indicatorWidth = itemWidth - 8;

                          final animatedLeft =
                              (_dragging
                                  ? (_dragIndicatorPage.clamp(
                                          0,
                                          itemCount - 1,
                                        ) *
                                        itemWidth)
                                  : (_page.clamp(0, itemCount - 1) *
                                        itemWidth)) +
                              4;

                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (details) {
                              _dragAccumX = 0;
                              setState(() {
                                _dragging = true;
                                _dragStartPage = _page;
                                _dragIndicatorPage = _page;
                              });
                            },
                            onPanUpdate: (details) {
                              _dragAccumX += details.delta.dx;
                              final deltaPages = _dragAccumX / itemWidth;
                              final double newPage =
                                  (_dragStartPage + deltaPages).clamp(
                                    0.0,
                                    (itemCount - 1).toDouble(),
                                  );
                              setState(() {
                                _dragIndicatorPage = newPage;
                              });
                              if (_pageController.hasClients &&
                                  _pageController.position.haveDimensions) {
                                final w =
                                    _pageController.position.viewportDimension;
                                _pageController.position.jumpTo(newPage * w);
                              }
                            },
                            onPanEnd: (details) {
                              final target = _dragIndicatorPage.round();
                              setState(() {
                                _dragging = false;
                              });
                              _goTo(target);
                            },
                            child: SizedBox(
                              height: 48,
                              child: Stack(
                                children: [
                                  // Animated pill indicator behind icons
                                  Positioned(
                                    left: animatedLeft,
                                    top: 4,
                                    width: indicatorWidth,
                                    height: 40,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      curve: Curves.easeOut,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.primary.withValues(
                                              alpha: 0.38,
                                            ),
                                            AppColors.secondary.withValues(
                                              alpha: 0.30,
                                            ),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: AppColors.secondary.withValues(
                                            alpha: 0.35,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Icons row (equal width slots, strictly centered)
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: itemWidth,
                                        child: Center(
                                          child: _NavIcon(
                                            icon: Icons.home_rounded,
                                            outline: Icons.home_outlined,
                                            selected: (_page.round() == 0),
                                            onTap: () => _goTo(0),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: Center(
                                          child: _NavIcon(
                                            icon: Icons.bar_chart_rounded,
                                            outline: Icons.bar_chart_rounded,
                                            selected: (_page.round() == 1),
                                            onTap: () => _goTo(1),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: Center(
                                          child: _NavIcon(
                                            icon: Icons.person_rounded,
                                            outline:
                                                Icons.person_outline_rounded,
                                            selected: (_page.round() == 2),
                                            onTap: () => _goTo(2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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

          // Animated themed FAB above navbar (rendered last to be on top)
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 110, right: 20),
                child: AnimatedBuilder(
                  animation: _fabBob,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _fabBob.value),
                    child: child,
                  ),
                  child: GestureDetector(
                    onTap: () async {
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
                                color: AppColors.background,
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
                        final profileState = _profileKey.currentState;

                        debugPrint(
                          'Home state: ${homeState != null ? "Found ✓" : "NULL ✗"}',
                        );
                        debugPrint(
                          'Statistics state: ${statisticsState != null ? "Found ✓" : "NULL ✗"}',
                        );
                        debugPrint(
                          'Profile state: ${profileState != null ? "Found ✓" : "NULL ✗"}',
                        );

                        // Refresh all screens
                        if (homeState != null) {
                          await homeState.refreshData();
                        }
                        if (statisticsState != null) {
                          await statisticsState.refreshData();
                        }
                        if (profileState != null) {
                          profileState.refreshData();
                        }

                        debugPrint('✅ All screens refresh triggered');
                      }
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 16,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.add, size: 28, color: Colors.white),
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
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    // Refresh statistics screen when navigating to it
    if (index == 1) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _statisticsKey.currentState?.refreshData();
      });
    }
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final IconData outline;
  final bool selected;
  final VoidCallback onTap;
  const _NavIcon({
    required this.icon,
    required this.outline,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            selected ? icon : outline,
            key: ValueKey<bool>(selected),
            size: selected ? 24 : 22,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}
