// lib/views/screens/bottomnavbarscreen/borrow_lend_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show
        showCupertinoModalPopup,
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTheme,
        CupertinoThemeData,
        CupertinoTextThemeData,
        CupertinoButton;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/debt.dart';
import '../../../services/debt_service.dart';
import '../../../utils/colors.dart';
import '../../../utils/format_utils.dart';
import '../../../services/Network_services.dart';
import '../../../utils/app_snackbar.dart';
import '../../../services/preference_service.dart';
import '../../widgets/buddy_loading_indicator.dart';
import '../../widgets/buddy_refresh_control.dart';

class BorrowLendScreen extends StatefulWidget {
  const BorrowLendScreen({super.key});

  @override
  State<BorrowLendScreen> createState() => BorrowLendScreenState();
}

class BorrowLendScreenState extends State<BorrowLendScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final DebtService _debtService = DebtService.instance;
  final ScrollController _scrollController = ScrollController();

  late Stream<List<DebtModel>> _debtsStream;
  List<DebtModel> _cachedDebts = const [];

  int _typeFilter = 0; // 0 = All, 1 = Lent (To Receive), 2 = Borrowed (To Pay)
  int _statusFilter = 0; // 0 = All (default), 1 = Pending, 2 = Settled
  bool _includeDebtsInHome = true;

  late final PageController _typeFilterPageController;
  double _headerDragAccumX = 0;
  double _headerDragStartPage = 0;
  int _lastHeaderHapticIndex = 0;

  double _segDragAccumX = 0;
  double _segDragStartPage = 0;
  int _lastSegHapticIndex = 0;

  late final AnimationController _statusFilterAnimController;
  double _statusSegDragAccumX = 0;
  double _statusSegDragStartVal = 0;
  int _lastStatusHapticIndex = 0;

  bool get _isSeparate => !_includeDebtsInHome;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _typeFilterPageController = PageController(initialPage: _typeFilter);
    _statusFilterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: _statusFilter.toDouble(),
      lowerBound: 0.0,
      upperBound: 2.0,
    );
    _debtsStream = _debtService.getDebtsStream();
    _includeDebtsInHome = PreferenceService.includeDebtsInHome;
    PreferenceService.includeDebtsInHomeNotifier.addListener(_onPreferenceChanged);
  }

  void _onPreferenceChanged() {
    if (!mounted) return;
    final val = PreferenceService.includeDebtsInHome;
    if (_includeDebtsInHome != val) {
      setState(() => _includeDebtsInHome = val);
    }
  }

  void _onToggleType(int mode, {bool isUserAction = true}) {
    final double currentPage = (_typeFilterPageController.hasClients &&
            _typeFilterPageController.positions.length == 1 &&
            _typeFilterPageController.position.haveDimensions)
        ? (_typeFilterPageController.page ?? _typeFilter.toDouble())
        : _typeFilter.toDouble();
    final bool pageAlreadyThere = (currentPage - mode).abs() < 0.01;
    if (_typeFilter == mode && pageAlreadyThere) return;
    if (isUserAction) {
      HapticFeedback.lightImpact();
    }
    if (_typeFilter != mode) {
      setState(() => _typeFilter = mode);
    }
    if (_typeFilterPageController.hasClients &&
        _typeFilterPageController.positions.length == 1 &&
        _typeFilterPageController.position.haveDimensions) {
      _typeFilterPageController.animateToPage(
        mode,
        duration: Duration(milliseconds: isUserAction ? 280 : 400),
        curve: Curves.easeOutCubic,
      ).then((_) {
        if (mounted && isUserAction) {
          HapticFeedback.mediumImpact();
        }
      });
    }
  }

  void _onToggleStatus(int mode, {bool isUserAction = true}) {
    final double currentVal = _statusFilterAnimController.value;
    final bool alreadyThere = (currentVal - mode).abs() < 0.01;
    if (_statusFilter == mode && alreadyThere) return;
    if (isUserAction) {
      HapticFeedback.lightImpact();
    }
    if (_statusFilter != mode) {
      setState(() => _statusFilter = mode);
    }
    _statusFilterAnimController.animateTo(
      mode.toDouble(),
      duration: Duration(milliseconds: isUserAction ? 260 : 360),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (mounted && isUserAction) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void dispose() {
    _typeFilterPageController.dispose();
    _statusFilterAnimController.dispose();
    PreferenceService.includeDebtsInHomeNotifier.removeListener(_onPreferenceChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHomeSyncPreference() async {
    if (mounted) {
      setState(() {
        _includeDebtsInHome = PreferenceService.includeDebtsInHome;
      });
    }
  }

  Future<void> _toggleSeparatePreference([bool? explicitSeparate]) async {
    HapticFeedback.lightImpact();
    final newSeparate = explicitSeparate ?? !_isSeparate;
    final newIncludeInHome = !newSeparate;
    await PreferenceService.setIncludeDebtsInHome(newIncludeInHome);
    if (!mounted) return;
    setState(() => _includeDebtsInHome = newIncludeInHome);
    AppSnackbar.showInfo(
      context,
      newSeparate
          ? 'Separate Mode ON: Dues won\'t affect your main wallet balance'
          : 'Combined Mode: Dues are added to your main wallet balance',
    );
  }

  Future<void> refreshData() async {
    _debtsStream = _debtService.getDebtsStream();
    await _loadHomeSyncPreference();
    if (mounted) setState(() {});
  }

  /// Called by the global FAB when on this tab. Pre-selects type based on
  /// current filter tab: Lent filter → opens Lend, Borrowed filter → opens Borrow.
  void openAddSheet() {
    // Map current type filter to initialType for the sheet
    // 0=All → no preference (Lend), 1=Lent → Lend, 2=Borrowed → Borrow
    final initialType = _typeFilter == 2 ? 1 : 0;
    _openAddEditSheet(context, initialType: initialType);
  }

  String _formatAmount(double amount) {
    return FormatUtils.formatCurrency(amount);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = AppColors.isDark(context);
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final topPadding = mq.padding.top;
    final double s = (screenW / 390.0).clamp(0.85, 1.25);
    final topHeaderColor = isDark
        ? const Color(0xFF0F2624)
        : const Color(0xFF0F3632);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.backgroundOf(context),
      body: StreamBuilder<List<DebtModel>>(
        stream: _debtsStream,
        initialData: _cachedDebts.isNotEmpty ? _cachedDebts : null,
        builder: (context, snapshot) {
          final allDebts = snapshot.data ?? _cachedDebts;
          if (snapshot.hasData && snapshot.data != null) {
            _cachedDebts = snapshot.data!;
          }
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData &&
                  _cachedDebts.isEmpty;

          // Compute summary metrics (only pending counts towards active balance)
          double totalLentPending = 0;
          double totalBorrowedPending = 0;
          int lentPendingCount = 0;
          int borrowPendingCount = 0;
          final dueTodayOrOverdue = <DebtModel>[];

          for (final d in allDebts) {
            if (!d.isRepaid) {
              if (d.isLend) {
                totalLentPending += d.amount;
                lentPendingCount++;
              } else {
                totalBorrowedPending += d.amount;
                borrowPendingCount++;
              }
              if (d.isDueToday || d.isOverdue) {
                dueTodayOrOverdue.add(d);
              }
            }
          }

          final netBalance = totalLentPending - totalBorrowedPending;

          // Filter debts
          final hasFilters = _typeFilter != 0 || _statusFilter != 0;
          final filteredDebts = allDebts.where((d) {
            // Type Filter: 0 = All, 1 = Lent (To Receive), 2 = Borrow (To Pay)
            if (_typeFilter == 1 && !d.isLend) return false;
            if (_typeFilter == 2 && !d.isBorrow) return false;

            // Status Filter: 0 = All, 1 = Pending, 2 = Settled
            if (_statusFilter == 1 && d.isRepaid) return false;
            if (_statusFilter == 2 && !d.isRepaid) return false;

            return true;
          }).toList();

          return Stack(
            children: [
              // Dynamic overscroll header backdrop: ONLY visible when pulling down past top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _scrollController,
                  builder: (context, _) {
                    final offset =
                        _scrollController.hasClients ? _scrollController.offset : 0.0;
                    final overscroll = offset < 0 ? -offset : 0.0;
                    if (overscroll <= 0) return const SizedBox.shrink();
                    return Container(
                      height: topPadding + overscroll + 40,
                      color: topHeaderColor,
                    );
                  },
                ),
              ),

              CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // Dynamic pull-to-refresh matching signature emerald header
                  BuddyRefreshControl(
                    onRefresh: refreshData,
                    backgroundColor: topHeaderColor,
                    topPadding: topPadding,
                  ),

                  // ── Signature Curved Hero Header ──
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: _buildHeroHeader(
                        context: context,
                        isDark: isDark,
                        topPadding: topPadding,
                        s: s,
                        netBalance: netBalance,
                        totalLentPending: totalLentPending,
                        totalBorrowedPending: totalBorrowedPending,
                        lentPendingCount: lentPendingCount,
                        borrowPendingCount: borrowPendingCount,
                        allDebtsCount: allDebts.length,
                      ),
                    ),
                  ),

                  // ── Sub-header: Compact Status Slider (All | Pending | Settled) ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, (8 * s).clamp(6.0, 10.0), 16, 6),
                      child: _buildStatusSlider(context, allDebts, s),
                    ),
                  ),

                  // ── Debts List, Loading, or Empty State ──
                  if (isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: BuddyLoadingIndicator(size: 56),
                      ),
                    )
                  else if (filteredDebts.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: _buildEmptyState(context, hasFilters),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildDebtCard(
                              context,
                              filteredDebts[index],
                              isDark,
                            );
                          },
                          childCount: filteredDebts.length,
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

  // ─── TOP CURVED HERO HEADER (Matching HomeScreen & StatisticsScreen) ───
  Widget _buildHeroHeader({
    required BuildContext context,
    required bool isDark,
    required double topPadding,
    required double s,
    required double netBalance,
    required double totalLentPending,
    required double totalBorrowedPending,
    required int lentPendingCount,
    required int borrowPendingCount,
    required int allDebtsCount,
  }) {
    final isAllSettled = netBalance.abs() < 0.01 &&
        totalLentPending < 0.01 &&
        totalBorrowedPending < 0.01;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (details) {
        _headerDragAccumX = 0;
        _headerDragStartPage = (_typeFilterPageController.hasClients &&
                _typeFilterPageController.positions.length == 1 &&
                _typeFilterPageController.position.haveDimensions)
            ? (_typeFilterPageController.page ?? _typeFilter.toDouble())
            : _typeFilter.toDouble();
        _lastHeaderHapticIndex = _headerDragStartPage.round();
        HapticFeedback.lightImpact();
      },
      onHorizontalDragUpdate: (details) {
        _headerDragAccumX += details.delta.dx;
        final double w = (_typeFilterPageController.hasClients &&
                _typeFilterPageController.positions.length == 1 &&
                _typeFilterPageController.position.haveDimensions)
            ? _typeFilterPageController.position.viewportDimension
            : MediaQuery.of(context).size.width;
        final double deltaPages =
            _headerDragAccumX / (w > 0 ? w : 300.0);
        final double newPage =
            (_headerDragStartPage + deltaPages).clamp(0.0, 2.0);
        if (_typeFilterPageController.hasClients &&
            _typeFilterPageController.positions.length == 1 &&
            _typeFilterPageController.position.haveDimensions) {
          _typeFilterPageController.position.jumpTo(newPage * w);
        }
        final int nearest = newPage.round().clamp(0, 2);
        if (nearest != _lastHeaderHapticIndex) {
          _lastHeaderHapticIndex = nearest;
          HapticFeedback.lightImpact();
        }
      },
      onHorizontalDragEnd: (details) {
        final double velocity = details.primaryVelocity ?? 0;
        final double currentP = (_typeFilterPageController.hasClients &&
                _typeFilterPageController.positions.length == 1 &&
                _typeFilterPageController.position.haveDimensions)
            ? (_typeFilterPageController.page ?? _typeFilter.toDouble())
            : _typeFilter.toDouble();
        int target = currentP.round();
        if (velocity > 250) {
          target = (currentP.floor() + 1).clamp(0, 2);
        } else if (velocity < -250) {
          target = (currentP.ceil() - 1).clamp(0, 2);
        }
        _onToggleType(target.clamp(0, 2));
      },
      onHorizontalDragCancel: () {
        final double currentP = (_typeFilterPageController.hasClients &&
                _typeFilterPageController.positions.length == 1 &&
                _typeFilterPageController.position.haveDimensions)
            ? (_typeFilterPageController.page ?? _typeFilter.toDouble())
            : _typeFilter.toDouble();
        _onToggleType(currentP.round().clamp(0, 2));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [
                    Color(0xFF0F2624), // Deep spruce/emerald
                    Color(0xFF163E3B), // Signature deep teal
                    Color(0xFF1E5D57), // Teal glow
                  ]
                : const [
                    Color(0xFF0F3632), // Signature dark emerald
                    Color(0xFF1E5D57), // Signature primary teal
                    Color(0xFF2C7A72), // Radiant teal highlight
                  ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular((32 * s).clamp(26.0, 38.0)),
            bottomRight: Radius.circular((32 * s).clamp(26.0, 38.0)),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F3632).withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            (20 * s).clamp(16.0, 24.0),
            topPadding + (10 * s).clamp(6.0, 14.0),
            (20 * s).clamp(16.0, 24.0),
            (20 * s).clamp(16.0, 24.0),
          ),
          child: Column(
            children: [
              // ── Top Bar: Title & Subtitle + Home Sync Button ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Borrow & Lend',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: (24 * s).clamp(21.0, 27.0),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Track friend dues, debts & repayments',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: (11.5 * s).clamp(10.5, 12.5),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Financial Integration Toggle (Separate vs. Combined)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => _showHomeSyncInfoDialog(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(
                              Icons.info_outline_rounded,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _toggleSeparatePreference(),
                          child: Text(
                            'Separate',
                            style: TextStyle(
                              color: _isSeparate
                                  ? const Color(0xFF69F0AE)
                                  : Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          height: 20,
                          width: 32,
                          child: Transform.scale(
                            scale: 0.65,
                            child: Switch.adaptive(
                              value: _isSeparate,
                              activeTrackColor: const Color(0xFF10B981),
                              activeThumbColor: Colors.white,
                              inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                              inactiveThumbColor: Colors.white70,
                              onChanged: (val) => _toggleSeparatePreference(val),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: (16 * s).clamp(12.0, 20.0)),

              // ─── Center Hero: Dynamic Label (Real-time scrub & cross-fade) ───
              SizedBox(
                height: (20 * s).clamp(18.0, 24.0),
                child: AnimatedBuilder(
                  animation: _typeFilterPageController,
                  builder: (context, _) {
                    final double currentPage = (_typeFilterPageController.hasClients &&
                            _typeFilterPageController.positions.length == 1 &&
                            _typeFilterPageController.position.haveDimensions)
                        ? (_typeFilterPageController.page ?? _typeFilter.toDouble())
                        : _typeFilter.toDouble();

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildHeroLabel(0, 'Net Balance', Icons.account_balance_wallet_outlined, currentPage, s),
                        _buildHeroLabel(1, 'To Receive (Lent)', Icons.north_east_rounded, currentPage, s),
                        _buildHeroLabel(2, 'To Pay (Borrowed)', Icons.south_west_rounded, currentPage, s),
                      ],
                    );
                  },
                ),
              ),

              SizedBox(height: (4 * s).clamp(2.0, 6.0)),

              // ─── Swipable Large Amount (Controlled seamlessly via top-level drag) ───
              SizedBox(
                height: (48 * s).clamp(40.0, 56.0),
                child: PageView(
                  controller: _typeFilterPageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) {
                    if (_typeFilter != i) {
                      setState(() => _typeFilter = i);
                    }
                  },
                  children: [
                    // Page 0: Net Balance
                    Center(
                      child: Text(
                        isAllSettled
                            ? '₹0.00'
                            : '${netBalance >= 0 ? '+' : '-'}${_formatAmount(netBalance.abs())}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: (30 * s).clamp(26.0, 36.0),
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Page 1: To Receive (Lent)
                    Center(
                      child: Text(
                        totalLentPending < 0.01
                            ? '₹0.00'
                            : '+${_formatAmount(totalLentPending)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: (30 * s).clamp(26.0, 36.0),
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF69F0AE),
                          letterSpacing: -0.8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Page 2: To Pay (Borrowed)
                    Center(
                      child: Text(
                        totalBorrowedPending < 0.01
                            ? '₹0.00'
                            : '-${_formatAmount(totalBorrowedPending)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: (30 * s).clamp(26.0, 36.0),
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFFF8A80),
                          letterSpacing: -0.8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: (6 * s).clamp(4.0, 8.0)),

              // ─── Centered Trend Capsule (Cross-fading with real-time scrub) ───
              AnimatedBuilder(
                animation: _typeFilterPageController,
                builder: (context, _) {
                  final double currentPage = (_typeFilterPageController.hasClients &&
                          _typeFilterPageController.positions.length == 1 &&
                          _typeFilterPageController.position.haveDimensions)
                      ? (_typeFilterPageController.page ?? _typeFilter.toDouble())
                      : _typeFilter.toDouble();

                  Color badgeBgColor;
                  Color badgeBorderColor;
                  if (currentPage <= 1.0) {
                    final double t = currentPage.clamp(0.0, 1.0);
                    badgeBgColor = Color.lerp(
                      isAllSettled
                          ? Colors.white.withValues(alpha: 0.16)
                          : (netBalance >= 0
                              ? const Color(0xFF69F0AE).withValues(alpha: 0.22)
                              : const Color(0xFFFF8A80).withValues(alpha: 0.22)),
                      const Color(0xFF69F0AE).withValues(alpha: 0.22),
                      t,
                    )!;
                    badgeBorderColor = Color.lerp(
                      isAllSettled
                          ? Colors.white.withValues(alpha: 0.3)
                          : (netBalance >= 0
                              ? const Color(0xFF69F0AE).withValues(alpha: 0.5)
                              : const Color(0xFFFF8A80).withValues(alpha: 0.5)),
                      const Color(0xFF69F0AE).withValues(alpha: 0.5),
                      t,
                    )!;
                  } else {
                    final double t = (currentPage - 1.0).clamp(0.0, 1.0);
                    badgeBgColor = Color.lerp(
                      const Color(0xFF69F0AE).withValues(alpha: 0.22),
                      const Color(0xFFFF8A80).withValues(alpha: 0.22),
                      t,
                    )!;
                    badgeBorderColor = Color.lerp(
                      const Color(0xFF69F0AE).withValues(alpha: 0.5),
                      const Color(0xFFFF8A80).withValues(alpha: 0.5),
                      t,
                    )!;
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeBgColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: badgeBorderColor),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildHeroBadge(
                          0,
                          isAllSettled
                              ? Icons.check_circle_outline_rounded
                              : (netBalance >= 0
                                  ? Icons.arrow_circle_up_rounded
                                  : Icons.arrow_circle_down_rounded),
                          isAllSettled
                              ? 'All Settled'
                              : (netBalance >= 0 ? 'You are owed net' : 'You owe net'),
                          isAllSettled
                              ? Colors.white
                              : (netBalance >= 0
                                  ? const Color(0xFF69F0AE)
                                  : const Color(0xFFFF8A80)),
                          currentPage,
                          s,
                        ),
                        _buildHeroBadge(
                          1,
                          lentPendingCount == 0
                              ? Icons.check_circle_outline_rounded
                              : Icons.arrow_circle_up_rounded,
                          lentPendingCount == 0
                              ? 'No Pending Dues'
                              : '$lentPendingCount Pending to Receive',
                          const Color(0xFF69F0AE),
                          currentPage,
                          s,
                        ),
                        _buildHeroBadge(
                          2,
                          borrowPendingCount == 0
                              ? Icons.check_circle_outline_rounded
                              : Icons.arrow_circle_down_rounded,
                          borrowPendingCount == 0
                              ? 'No Pending Dues'
                              : '$borrowPendingCount Pending to Pay',
                          const Color(0xFFFF8A80),
                          currentPage,
                          s,
                        ),
                      ],
                    ),
                  );
                },
              ),

              SizedBox(height: (16 * s).clamp(12.0, 20.0)),

              // ── Integrated Frosted 3-Tab Slider (All | To Receive | To Pay) ──
              _buildTypeSlider(s),
            ],
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.only(
          top: (10 * s).clamp(8.0, 14.0),
          bottom: (2 * s).clamp(0.0, 4.0),
        ),
        child: _buildSwipeIndicator(s),
      ),
    ],
  ),
);
  }

  Widget _buildHeroLabel(
    int index,
    String text,
    IconData icon,
    double currentPage,
    double s,
  ) {
    final double dist = (currentPage - index).abs();
    final double opacity = (1.0 - dist).clamp(0.0, 1.0);
    if (opacity <= 0.001) return const SizedBox.shrink();

    final double translateX = (index - currentPage) * 16.0;

    return Transform.translate(
      offset: Offset(translateX, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: Colors.white.withValues(alpha: (0.8 * opacity).clamp(0.0, 1.0)),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: (12.5 * s).clamp(11.5, 14.0),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: Colors.white.withValues(alpha: (0.85 * opacity).clamp(0.0, 1.0)),
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge(
    int index,
    IconData icon,
    String text,
    Color color,
    double currentPage,
    double s,
  ) {
    final double dist = (currentPage - index).abs();
    final double opacity = (1.0 - dist).clamp(0.0, 1.0);
    if (opacity <= 0.001) return const SizedBox.shrink();

    final double translateX = (index - currentPage) * 14.0;

    return Transform.translate(
      offset: Offset(translateX, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TYPE SLIDER (Matching HomeScreen 3-segment toggle bar with drag & scrub) ───
  Widget _buildTypeSlider(double s) {
    final height = (40 * s).clamp(36.0, 44.0);

    return Container(
      height: height,
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
          final totalWidth = constraints.maxWidth;
          const int itemCount = 3;
          final segWidth = totalWidth / itemCount;
          const double pillInset = 1.0;
          final double pillWidth = segWidth - (2 * pillInset);

          return AnimatedBuilder(
            animation: _typeFilterPageController,
            builder: (context, _) {
              final double currentPage = (_typeFilterPageController.hasClients &&
                      _typeFilterPageController.positions.length == 1 &&
                      _typeFilterPageController.position.haveDimensions)
                  ? (_typeFilterPageController.page ?? _typeFilter.toDouble())
                  : _typeFilter.toDouble();

              final double leftOffset = (currentPage * segWidth + pillInset)
                  .clamp(pillInset, totalWidth - segWidth + pillInset);

              Color c1, c2, borderC, glowC;
              if (currentPage <= 1.0) {
                final double t = currentPage.clamp(0.0, 1.0);
                c1 = Color.lerp(
                  Colors.white.withValues(alpha: 0.28),
                  const Color(0xFF10B981).withValues(alpha: 0.38),
                  t,
                )!;
                c2 = Color.lerp(
                  Colors.white.withValues(alpha: 0.15),
                  const Color(0xFF10B981).withValues(alpha: 0.22),
                  t,
                )!;
                borderC = Color.lerp(
                  Colors.white.withValues(alpha: 0.45),
                  const Color(0xFF10B981).withValues(alpha: 0.60),
                  t,
                )!;
                glowC = Color.lerp(
                  Colors.white.withValues(alpha: 0.15),
                  const Color(0xFF10B981).withValues(alpha: 0.25),
                  t,
                )!;
              } else {
                final double t = (currentPage - 1.0).clamp(0.0, 1.0);
                c1 = Color.lerp(
                  const Color(0xFF10B981).withValues(alpha: 0.38),
                  AppColors.expense.withValues(alpha: 0.38),
                  t,
                )!;
                c2 = Color.lerp(
                  const Color(0xFF10B981).withValues(alpha: 0.22),
                  AppColors.expense.withValues(alpha: 0.22),
                  t,
                )!;
                borderC = Color.lerp(
                  const Color(0xFF10B981).withValues(alpha: 0.60),
                  AppColors.expense.withValues(alpha: 0.60),
                  t,
                )!;
                glowC = Color.lerp(
                  const Color(0xFF10B981).withValues(alpha: 0.25),
                  AppColors.expense.withValues(alpha: 0.25),
                  t,
                )!;
              }

              final pillGradient = LinearGradient(
                colors: [c1, c2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              );

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) {
                  _segDragAccumX = 0;
                  _segDragStartPage = currentPage;
                  _lastSegHapticIndex = currentPage.round();
                  HapticFeedback.lightImpact();
                },
                onHorizontalDragUpdate: (details) {
                  _segDragAccumX += details.delta.dx;
                  final double deltaPages = _segDragAccumX / segWidth;
                  final double newPage =
                      (_segDragStartPage + deltaPages).clamp(0.0, 2.0);
                  if (_typeFilterPageController.hasClients &&
                      _typeFilterPageController.positions.length == 1 &&
                      _typeFilterPageController.position.haveDimensions) {
                    final double w = _typeFilterPageController
                        .position.viewportDimension;
                    _typeFilterPageController.position.jumpTo(newPage * w);
                  }
                  final int nearest = newPage.round().clamp(0, 2);
                  if (nearest != _lastSegHapticIndex) {
                    _lastSegHapticIndex = nearest;
                    HapticFeedback.lightImpact();
                  }
                },
                onHorizontalDragEnd: (details) {
                  final double velocity = details.primaryVelocity ?? 0;
                  final double currentP = (_typeFilterPageController.hasClients &&
                          _typeFilterPageController.positions.length == 1 &&
                          _typeFilterPageController.position.haveDimensions)
                      ? (_typeFilterPageController.page ?? currentPage)
                      : currentPage;
                  int target = currentP.round();
                  if (velocity > 250) {
                    target = (currentP.floor() + 1).clamp(0, 2);
                  } else if (velocity < -250) {
                    target = (currentP.ceil() - 1).clamp(0, 2);
                  }
                  _onToggleType(target.clamp(0, 2));
                },
                onHorizontalDragCancel: () {
                  final int target = (_typeFilterPageController.hasClients &&
                          _typeFilterPageController.positions.length == 1 &&
                          _typeFilterPageController.position.haveDimensions)
                      ? (_typeFilterPageController.page ?? currentPage).round().clamp(0, 2)
                      : currentPage.round().clamp(0, 2);
                  _onToggleType(target);
                },
                child: SizedBox(
                  height: height,
                  child: Stack(
                    children: [
                      Positioned(
                        left: leftOffset,
                        width: pillWidth,
                        top: 1,
                        bottom: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: pillGradient,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: borderC,
                              width: 1.1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: glowC,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTypeToggleTab(0, 'All', null, currentPage, s),
                          ),
                          Expanded(
                            child: _buildTypeToggleTab(1, 'To Receive', Icons.north_east_rounded, currentPage, s),
                          ),
                          Expanded(
                            child: _buildTypeToggleTab(2, 'To Pay', Icons.south_west_rounded, currentPage, s),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTypeToggleTab(
    int index,
    String label,
    IconData? icon,
    double currentPage,
    double s,
  ) {
    final double dist = (currentPage - index).abs();
    final double activeFactor = (1.0 - dist).clamp(0.0, 1.0);

    Color activeIconColor;
    if (index == 1) {
      activeIconColor = const Color(0xFF69F0AE);
    } else if (index == 2) {
      activeIconColor = const Color(0xFFFF8A80);
    } else {
      activeIconColor = Colors.white;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onToggleType(index),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: (13 * s).clamp(11.0, 15.0),
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.60),
                  activeIconColor,
                  activeFactor,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color.lerp(
                    Colors.white.withValues(alpha: 0.60),
                    Colors.white,
                    activeFactor,
                  ),
                  fontSize: (12.0 * s).clamp(10.5, 13.5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeIndicator(double s) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _typeFilterPageController,
      builder: (context, _) {
        final double currentPage = (_typeFilterPageController.hasClients &&
                _typeFilterPageController.positions.length == 1 &&
                _typeFilterPageController.position.haveDimensions)
            ? (_typeFilterPageController.page ?? _typeFilter.toDouble())
            : _typeFilter.toDouble();

        return Center(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: (8 * s).clamp(7.0, 11.0),
              vertical: (3.5 * s).clamp(3.0, 5.0),
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFF0F3632).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : const Color(0xFF0F3632).withValues(alpha: 0.16),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : const Color(0xFF0F3632))
                      .withValues(alpha: isDark ? 0.20 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSwipeDot(0, currentPage, s, isDark),
                SizedBox(width: (4.5 * s).clamp(3.5, 6.0)),
                _buildSwipeDot(1, currentPage, s, isDark),
                SizedBox(width: (4.5 * s).clamp(3.5, 6.0)),
                _buildSwipeDot(2, currentPage, s, isDark),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSwipeDot(int index, double currentPage, double s, bool isDark) {
    final double dist = (currentPage - index).abs().clamp(0.0, 1.0);
    final double factor = 1.0 - dist;
    final double dotWidth = (5.0 + 11.0 * factor) * s;
    final double dotHeight = (4.5 * s).clamp(4.0, 5.5);

    Color activeColor;
    if (index == 1) {
      activeColor = const Color(0xFF69F0AE);
    } else if (index == 2) {
      activeColor = const Color(0xFFFF8A80);
    } else {
      activeColor = isDark ? Colors.white : const Color(0xFF0F3632);
    }

    final Color inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : const Color(0xFF0F3632).withValues(alpha: 0.22);

    final Color dotColor = Color.lerp(
      inactiveColor,
      activeColor,
      factor,
    )!;

    return Container(
      width: dotWidth,
      height: dotHeight,
      decoration: BoxDecoration(
        color: dotColor,
        borderRadius: BorderRadius.circular(dotHeight / 2),
      ),
    );
  }

  /// Informational sheet explaining whether borrow & lend is separate or combined in plain English.
  void _showHomeSyncInfoDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        final isShort = screenHeight < 720;

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: screenHeight * 0.88,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardOf(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(ctx).padding.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: AppColors.borderOf(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      SizedBox(height: isShort ? 12 : 18),

                      // Icon badge
                      Container(
                        width: isShort ? 46 : 54,
                        height: isShort ? 46 : 54,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF69AEA9), Color(0xFF3F8782)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: isShort ? 22 : 26,
                        ),
                      ),
                      SizedBox(height: isShort ? 10 : 14),

                      // Title & Subtitle
                      Text(
                        'Keep Dues Separate?',
                        style: TextStyle(
                          fontSize: isShort ? 17.5 : 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimaryOf(context),
                          letterSpacing: -0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Choose if personal borrow & lend money changes your main wallet balance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isShort ? 12 : 13,
                          height: 1.35,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                      SizedBox(height: isShort ? 12 : 18),

                      // Interactive Switch Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isSeparate
                                ? AppColors.primary.withValues(alpha: 0.45)
                                : AppColors.borderOf(context),
                            width: _isSeparate ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: (_isSeparate
                                        ? AppColors.primary
                                        : AppColors.textLightOf(context))
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isSeparate
                                    ? Icons.layers_clear_outlined
                                    : Icons.account_balance_wallet_outlined,
                                size: 18,
                                color: _isSeparate
                                    ? AppColors.primary
                                    : AppColors.textSecondaryOf(context),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Keep Separate',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimaryOf(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isSeparate
                                        ? 'ON: Dues stay only in this tab'
                                        : 'OFF (Default): Dues are combined with your wallet balance',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _isSeparate
                                          ? AppColors.primary
                                          : AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _isSeparate,
                              activeTrackColor: AppColors.primary,
                              activeThumbColor: Colors.white,
                              onChanged: (val) async {
                                await _toggleSeparatePreference(val);
                                setModalState(() {});
                              },
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isShort ? 10 : 14),

                      // Explanatory points in plain English
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.borderOf(context).withValues(alpha: 0.6),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildInfoBullet(
                              icon: Icons.check_circle_outline_rounded,
                              iconColor: const Color(0xFF10B981),
                              title: 'When OFF (Default — Combined)',
                              desc:
                                  'Money friends owe you is added to your total balance. Money you owe others is taken out. Both reflect in Home and Statistics.',
                            ),
                            SizedBox(height: isShort ? 8 : 12),
                            _buildInfoBullet(
                              icon: Icons.visibility_off_outlined,
                              iconColor: AppColors.expense,
                              title: 'When ON (Separate)',
                              desc:
                                  'Borrow & Lend stays only in this tab. Your main wallet balance and statistics will ignore your friend dues completely.',
                            ),
                            SizedBox(height: isShort ? 8 : 12),
                            _buildInfoBullet(
                              icon: Icons.cloud_done_rounded,
                              iconColor: AppColors.primary,
                              title: 'Saved to Your Account',
                              desc:
                                  'Your choice is automatically remembered across app restarts and re-installs.',
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isShort ? 12 : 18),

                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Got It',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoBullet({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── COMPACT STATUS SLIDER (All | Pending | Settled with Swiping & Drag) ───
  Widget _buildStatusSlider(
    BuildContext context,
    List<DebtModel> allDebts,
    double s,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scopedDebts = allDebts.where((d) {
      if (_typeFilter == 1 && !d.isLend) return false;
      if (_typeFilter == 2 && !d.isBorrow) return false;
      return true;
    }).toList();

    final allCount = scopedDebts.length;
    final pendingCount = scopedDebts.where((d) => !d.isRepaid).length;
    final settledCount = scopedDebts.where((d) => d.isRepaid).length;

    final height = (38 * s).clamp(34.0, 42.0);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFF0F3632).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFF0F3632).withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(2.5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          const int itemCount = 3;
          final segWidth = totalWidth / itemCount;
          const double pillInset = 1.0;
          final double pillWidth = segWidth - (2 * pillInset);

          return AnimatedBuilder(
            animation: _statusFilterAnimController,
            builder: (context, _) {
              final double currentVal = _statusFilterAnimController.value;
              final double leftOffset = (currentVal * segWidth + pillInset)
                  .clamp(pillInset, totalWidth - segWidth + pillInset);

              // Dynamic gradient across 0 (All) -> 1 (Pending) -> 2 (Settled)
              Color c1, c2, borderC, glowC;
              if (currentVal <= 1.0) {
                final double t = currentVal.clamp(0.0, 1.0);
                c1 = Color.lerp(
                  isDark ? const Color(0xFF1E5D57) : const Color(0xFF0F3632),
                  const Color(0xFFD97706),
                  t,
                )!;
                c2 = Color.lerp(
                  isDark ? const Color(0xFF163E3B) : const Color(0xFF1E5D57),
                  const Color(0xFFB45309),
                  t,
                )!;
                borderC = Color.lerp(
                  isDark
                      ? const Color(0xFF69F0AE).withValues(alpha: 0.35)
                      : const Color(0xFF1E5D57).withValues(alpha: 0.40),
                  const Color(0xFFF59E0B).withValues(alpha: 0.60),
                  t,
                )!;
                glowC = Color.lerp(
                  const Color(0xFF1E5D57).withValues(alpha: 0.20),
                  const Color(0xFFD97706).withValues(alpha: 0.20),
                  t,
                )!;
              } else {
                final double t = (currentVal - 1.0).clamp(0.0, 1.0);
                c1 = Color.lerp(
                  const Color(0xFFD97706),
                  const Color(0xFF059669),
                  t,
                )!;
                c2 = Color.lerp(
                  const Color(0xFFB45309),
                  const Color(0xFF10B981),
                  t,
                )!;
                borderC = Color.lerp(
                  const Color(0xFFF59E0B).withValues(alpha: 0.60),
                  const Color(0xFF69F0AE).withValues(alpha: 0.60),
                  t,
                )!;
                glowC = Color.lerp(
                  const Color(0xFFD97706).withValues(alpha: 0.20),
                  const Color(0xFF059669).withValues(alpha: 0.20),
                  t,
                )!;
              }

              final pillGradient = LinearGradient(
                colors: [c1, c2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              );

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) {
                  _statusFilterAnimController.stop();
                  _statusSegDragAccumX = 0;
                  _statusSegDragStartVal = currentVal;
                  _lastStatusHapticIndex = currentVal.round();
                  HapticFeedback.lightImpact();
                },
                onHorizontalDragUpdate: (details) {
                  _statusSegDragAccumX += details.delta.dx;
                  final double deltaPages = _statusSegDragAccumX / segWidth;
                  final double newVal =
                      (_statusSegDragStartVal + deltaPages).clamp(0.0, 2.0);
                  _statusFilterAnimController.value = newVal;

                  final int nearest = newVal.round().clamp(0, 2);
                  if (nearest != _lastStatusHapticIndex) {
                    _lastStatusHapticIndex = nearest;
                    HapticFeedback.lightImpact();
                  }
                },
                onHorizontalDragEnd: (details) {
                  final double velocity = details.primaryVelocity ?? 0;
                  final double cur = _statusFilterAnimController.value;
                  int target = cur.round();
                  if (velocity > 250) {
                    target = (cur.floor() + 1).clamp(0, 2);
                  } else if (velocity < -250) {
                    target = (cur.ceil() - 1).clamp(0, 2);
                  }
                  _onToggleStatus(target.clamp(0, 2));
                },
                onHorizontalDragCancel: () {
                  _onToggleStatus(_statusFilterAnimController.value.round().clamp(0, 2));
                },
                child: SizedBox(
                  height: height,
                  child: Stack(
                    children: [
                      Positioned(
                        left: leftOffset,
                        width: pillWidth,
                        top: 1,
                        bottom: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: pillGradient,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: borderC,
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: glowC,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatusSliderTab(0, 'All', allCount, currentVal, s),
                          ),
                          Expanded(
                            child: _buildStatusSliderTab(1, 'Pending', pendingCount, currentVal, s),
                          ),
                          Expanded(
                            child: _buildStatusSliderTab(2, 'Settled', settledCount, currentVal, s),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusSliderTab(
    int index,
    String label,
    int count,
    double currentVal,
    double s,
  ) {
    final double dist = (currentVal - index).abs();
    final double activeFactor = (1.0 - dist).clamp(0.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final unselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.60)
        : const Color(0xFF0F3632).withValues(alpha: 0.65);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onToggleStatus(index),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color.lerp(unselectedColor, Colors.white, activeFactor),
                  fontSize: (11.5 * s).clamp(10.5, 13.0),
                  fontWeight: activeFactor > 0.5 ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Color.lerp(
                  isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFF0F3632).withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.26),
                  activeFactor,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: Color.lerp(unselectedColor, Colors.white, activeFactor),
                  fontSize: (10.0 * s).clamp(9.0, 11.0),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DEBT CARD ───
  Widget _buildDebtCard(
    BuildContext context,
    DebtModel debt,
    bool isDark,
  ) {
    final isLend = debt.isLend;
    final isRepaid = debt.isRepaid;
    final isOverdue = debt.isOverdue;
    final isDueToday = debt.isDueToday;
    final daysDiff = debt.daysDifference;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isRepaid) {
      if (debt.isRepaidOnTime) {
        statusColor = const Color(0xFF1EBE5D);
        final dateStr = debt.repaidDate != null
            ? DateFormat('dd MMM').format(debt.repaidDate!)
            : '';
        statusText = dateStr.isNotEmpty ? 'Paid on time ($dateStr)' : 'Paid on time';
        statusIcon = Icons.check_circle_rounded;
      } else if (debt.isRepaidLate) {
        statusColor = const Color(0xFFFF9800);
        final dateStr = debt.repaidDate != null
            ? DateFormat('dd MMM').format(debt.repaidDate!)
            : '';
        statusText = 'Paid ${debt.daysLateRepaid}d late${dateStr.isNotEmpty ? " ($dateStr)" : ""}';
        statusIcon = Icons.warning_amber_rounded;
      } else {
        statusColor = AppColors.income;
        statusText = debt.repaidDate != null
            ? 'Settled on ${DateFormat('dd MMM').format(debt.repaidDate!)}'
            : 'Settled';
        statusIcon = Icons.check_circle_rounded;
      }
    } else if (isDueToday) {
      statusColor = const Color(0xFFFF9800);
      statusText = 'Due Today!';
      statusIcon = Icons.alarm_rounded;
    } else if (isOverdue) {
      statusColor = AppColors.expense;
      final daysLate = daysDiff.abs();
      statusText = 'Overdue by $daysLate ${daysLate == 1 ? "day" : "days"}';
      statusIcon = Icons.warning_rounded;
    } else {
      statusColor = const Color(0xFF00897B);
      if (daysDiff == 1) {
        statusText = 'Due tomorrow';
      } else {
        statusText = 'Due in $daysDiff days';
      }
      statusIcon = Icons.schedule_rounded;
    }

    final initials = debt.personName.trim().isNotEmpty
        ? debt.personName
            .trim()
            .split(' ')
            .take(2)
            .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
            .join()
        : 'F';

    final accentStripeColor =
        isRepaid ? const Color(0xFF1EBE5D) : debt.urgencyColor;
    final borderColor = (isDueToday || isOverdue) && !isRepaid
        ? (isDueToday ? const Color(0xFFFF9800) : AppColors.expense)
            .withValues(alpha: 0.5)
        : AppColors.borderOf(context).withValues(alpha: 0.5);
    final borderWidth = (isDueToday || isOverdue) && !isRepaid ? 1.5 : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _showDebtDetailModal(context, debt),
                child: Padding(
                  padding: const EdgeInsets.only(left: 18.5, right: 14, top: 14, bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Top Row: Avatar + Name & Subtitle + Amount & Status ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isLend
                                        ? const [Color(0xFF26A69A), Color(0xFF00897B)]
                                        : const [Color(0xFFFF7043), Color(0xFFE65100)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(2.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardOf(context),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isRepaid
                                          ? const Color(0xFF1EBE5D)
                                          : (isDueToday
                                              ? const Color(0xFFFF9800)
                                              : (isOverdue
                                                  ? AppColors.expense
                                                  : const Color(0xFF00897B))),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),

                          // Name + Subtitle + Note
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        debt.personName.trim().isNotEmpty
                                            ? debt.personName.trim()
                                            : (isLend ? 'Friend (Lent)' : 'Friend (Borrowed)'),
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimaryOf(context),
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isLend
                                      ? 'Given on ${DateFormat('dd MMM yyyy').format(debt.date)}'
                                      : 'Taken on ${DateFormat('dd MMM yyyy').format(debt.date)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textLightOf(context),
                                  ),
                                ),
                                if (debt.note != null &&
                                    debt.note!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    debt.note!.trim(),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondaryOf(context),
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Amount Display + Micro Status Pill directly below
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isRepaid
                                    ? '${isLend ? '+' : '-'}${_formatAmount(debt.originalAmount)}'
                                    : '${isLend ? '+' : '-'}${_formatAmount(debt.amount)}',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color: isRepaid
                                      ? (isDark ? Colors.white70 : AppColors.textSecondary)
                                      : (isLend
                                          ? AppColors.income
                                          : AppColors.expense),
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, size: 10, color: statusColor),
                                    const SizedBox(width: 3.5),
                                    Text(
                                      statusText,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // ── Settlements & Repayment Breakdown ──
                      if (debt.hasPartialSettlements) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceOf(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.borderOf(context).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Repayment Progress',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                  Text(
                                    '${(debt.progressPercent * 100).toInt()}% • Paid ${_formatAmount(debt.totalPaid)} of ${_formatAmount(debt.originalAmount)}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: isLend ? AppColors.income : AppColors.expense,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: debt.progressPercent,
                                  backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.4),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isLend ? AppColors.income : AppColors.expense,
                                  ),
                                  minHeight: 4.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),
                      Divider(
                        height: 1,
                        color: AppColors.borderOf(context).withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8),

                      // Bottom Action Row (Responsive Wrap to prevent Settle button overflow)
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 13,
                                color: AppColors.textSecondaryOf(context),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Repay: ${DateFormat('dd MMM yyyy').format(debt.dueDate)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),

                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Remind Button (Only for Lent and Pending)
                              if (isLend && !isRepaid) ...[
                                _buildActionChip(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  label: 'Remind',
                                  color: const Color(0xFF1EBE5D),
                                  bgColor: const Color(0xFF25D366).withValues(alpha: 0.12),
                                  borderColor: const Color(0xFF25D366).withValues(alpha: 0.3),
                                  onTap: () => _sendReminder(debt),
                                ),
                                const SizedBox(width: 6),
                              ],

                              // Settle button — opens partial settle sheet for pending, reopen for settled
                              if (!isRepaid)
                                _buildActionChip(
                                  icon: Icons.payments_outlined,
                                  label: isLend ? 'Settle' : 'Repay',
                                  color: AppColors.primary,
                                  bgColor: AppColors.primary.withValues(alpha: 0.12),
                                  borderColor: AppColors.primary.withValues(alpha: 0.3),
                                  onTap: () => _showPartialSettleSheet(context, debt),
                                )
                              else
                                _buildActionChip(
                                  icon: Icons.undo_rounded,
                                  label: 'Reopen',
                                  color: AppColors.textSecondaryOf(context),
                                  bgColor: AppColors.surfaceOf(context),
                                  borderColor: AppColors.borderOf(context),
                                  onTap: () => _toggleSettled(debt),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Left accent stripe indicator
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4.5,
              child: ColoredBox(color: accentStripeColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.5, color: color),
            const SizedBox(width: 3.5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── EMPTY STATE ───
  // ─── EMPTY STATE ───
  Widget _buildEmptyState(BuildContext context, bool hasFilters) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.handshake_outlined,
              size: 48,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters
                ? 'No matching records'
                : 'No borrow or lend records yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilters
                ? 'Try selecting a different filter above'
                : 'Lend money to friends or track what you owe.\nAutomatic expense & income tracking built-in!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          if (hasFilters)
            ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _typeFilter = 0;
                  _statusFilter = 0;
                });
              },
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Show All Records'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => openAddSheet(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add First Record'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── SEND REMINDER SHARE ACTION ───
  Future<void> _sendReminder(DebtModel debt) async {
    HapticFeedback.lightImpact();
    final formattedAmount = _formatAmount(debt.amount);
    final formattedDate = DateFormat('dd MMM yyyy').format(debt.date);
    final formattedDueDate = DateFormat('dd MMM yyyy').format(debt.dueDate);

    final message = '''
Hi ${debt.personName},

Hope you are doing well! Just a friendly reminder regarding the $formattedAmount borrowed on $formattedDate.
As discussed, the expected repayment date was $formattedDueDate.

Please let me know once convenient to transfer. Thank you!''';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Friendly Repayment Reminder ($formattedAmount)',
        ),
      );
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Failed to open share: $e');
      }
    }
  }

  // ─── PARTIAL SETTLE BOTTOM SHEET ───
  Future<void> _showPartialSettleSheet(
    BuildContext context,
    DebtModel debt,
  ) async {
    HapticFeedback.mediumImpact();
    final isLend = debt.isLend;
    final totalAmount = debt.amount;
    final amountCtrl = TextEditingController(
      text: totalAmount.toStringAsFixed(0),
    );
    final noteCtrl = TextEditingController();
    double settledAmount = totalAmount;
    bool recordTxn = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            final accentColor = isLend ? AppColors.income : AppColors.expense;
            final isFullSettle = (settledAmount - totalAmount).abs() < 0.01;
            final remaining = (totalAmount - settledAmount).clamp(0.0, totalAmount);

            final isDark = Theme.of(context).brightness == Brightness.dark;

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.90,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.cardOf(sheetContext),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                        blurRadius: 28,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Unified Modal Header ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.borderOf(context),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.payments_rounded,
                                    color: accentColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isLend
                                            ? 'Settle Lent Amount'
                                            : 'Record Repayment',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimaryOf(context),
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        '${debt.personName} • Remaining: ${_formatAmount(totalAmount)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textSecondaryOf(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => Navigator.pop(ctx),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceOf(context),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.borderOf(context).withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: AppColors.textSecondaryOf(context),
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: AppColors.borderOf(context).withValues(alpha: 0.5),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          // Amount input
                    Text(
                      isLend
                          ? 'How much did they pay back?'
                          : 'How much are you repaying?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            '₹',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              decoration: InputDecoration(
                                hintText: '0',
                                hintStyle: TextStyle(
                                  color: AppColors.textLightOf(context),
                                  fontSize: 24,
                                ),
                                border: InputBorder.none,
                              ),
                              onChanged: (v) {
                                final parsed = double.tryParse(v.trim()) ?? 0;
                                setSheet(() {
                                  settledAmount =
                                      parsed.clamp(0.0, totalAmount);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Quick amount shortcuts
                    Row(
                      children: [
                        _quickAmountChip(
                          '25%',
                          (totalAmount * 0.25).roundToDouble(),
                          accentColor,
                          amountCtrl,
                          setSheet,
                          (v) => settledAmount = v,
                        ),
                        const SizedBox(width: 8),
                        _quickAmountChip(
                          '50%',
                          (totalAmount * 0.50).roundToDouble(),
                          accentColor,
                          amountCtrl,
                          setSheet,
                          (v) => settledAmount = v,
                        ),
                        const SizedBox(width: 8),
                        _quickAmountChip(
                          '75%',
                          (totalAmount * 0.75).roundToDouble(),
                          accentColor,
                          amountCtrl,
                          setSheet,
                          (v) => settledAmount = v,
                        ),
                        const SizedBox(width: 8),
                        _quickAmountChip(
                          'Full',
                          totalAmount,
                          accentColor,
                          amountCtrl,
                          setSheet,
                          (v) => settledAmount = v,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Settlement Note Input
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      child: TextField(
                        controller: noteCtrl,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimaryOf(context),
                        ),
                        decoration: InputDecoration(
                          icon: Icon(
                            Icons.edit_note_rounded,
                            size: 18,
                            color: AppColors.textLightOf(context),
                          ),
                          hintText: 'Note (optional, e.g. GPay, Cash, Part 1)',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: AppColors.textLightOf(context),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Summary info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _summaryCell(
                              context,
                              'Settling',
                              _formatAmount(settledAmount.clamp(0.0, totalAmount)),
                              accentColor,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: AppColors.borderOf(context),
                          ),
                          Expanded(
                            child: _summaryCell(
                              context,
                              isFullSettle
                                  ? '✅ Fully Settled'
                                  : 'Remaining',
                              isFullSettle
                                  ? 'Done!'
                                  : _formatAmount(remaining),
                              isFullSettle
                                  ? AppColors.income
                                  : AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Record transaction toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: CheckboxListTile(
                        value: recordTxn,
                        onChanged: (val) =>
                            setSheet(() => recordTxn = val ?? true),
                        activeColor: AppColors.primary,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          isLend
                              ? 'Record as Income in your tracker'
                              : 'Record as Expense in your tracker',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Confirm button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: settledAmount <= 0
                            ? null
                            : () async {
                                final noteText = noteCtrl.text.trim();
                                Navigator.pop(ctx);
                                await _debtService.partialSettle(
                                  debt: debt,
                                  settledAmount: settledAmount.clamp(
                                    0.0,
                                    totalAmount,
                                  ),
                                  recordTransaction: recordTxn,
                                  note: noteText.isNotEmpty ? noteText : null,
                                );
                                final isFully = (settledAmount - totalAmount).abs() < 0.01;
                                if (mounted) {
                                  AppSnackbar.showSuccess(
                                    this.context,
                                    isFully
                                        ? 'Fully settled!'
                                        : 'Partial payment of ${_formatAmount(settledAmount)} recorded.',
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.borderOf(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isFullSettle
                                ? (isLend ? 'Confirm Full Settlement' : 'Confirm Full Repayment')
                                : (isLend
                                    ? 'Record Partial Settlement'
                                    : 'Record Partial Repayment'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
            );
          },
        );
      },
    );
  }

  Widget _quickAmountChip(
    String label,
    double amount,
    Color accentColor,
    TextEditingController ctrl,
    StateSetter setSheet,
    void Function(double) onSet,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          final display = amount == amount.truncate()
              ? amount.toInt().toString()
              : amount.toStringAsFixed(2);
          ctrl.text = display;
          setSheet(() => onSet(amount));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCell(
    BuildContext context,
    String label,
    String value,
    Color valueColor,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ─── SETTLE / REOPEN DEBT (Full toggle used for "Reopen") ───
  Future<void> _toggleSettled(DebtModel debt) async {
    HapticFeedback.mediumImpact();
    // Only handles reopening a settled debt
    await _debtService.markAsRepaid(debt: debt, isRepaid: false);
    if (mounted) {
      AppSnackbar.showInfo(context, 'Record reopened as pending');
    }
  }

  // ─── DEBT DETAIL MODAL ───
  void _showDebtDetailModal(BuildContext context, DebtModel debt) {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLend = debt.isLend;
    final accentColor = isLend ? AppColors.income : AppColors.expense;

    // Get initials for Avatar
    final trimmedName = debt.personName.trim();
    final nameParts = trimmedName.split(RegExp(r'\s+'));
    final initials = nameParts.length > 1
        ? '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase()
        : (trimmedName.isNotEmpty ? trimmedName[0].toUpperCase() : '?');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── 1. Signature Page-Style Top Hero Container (From Top to End of Grid) ───
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? const [
                                Color(0xFF0F2624), // Deep spruce/emerald
                                Color(0xFF163E3B), // Signature deep teal
                                Color(0xFF1E5D57), // Teal glow
                              ]
                            : const [
                                Color(0xFF0F3632), // Signature dark emerald
                                Color(0xFF1E5D57), // Signature primary teal
                                Color(0xFF2C7A72), // Radiant teal highlight
                              ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? const Color(0xFF0F2624) : const Color(0xFF0F3632))
                              .withValues(alpha: 0.32),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(
                      children: [
                        // Frosted drag handle
                        Center(
                          child: Container(
                            width: 42,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Header Bar: Title & Subtitle + Frosted Action Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Due Record Details',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${debt.personName} • ${isLend ? "Money Lent" : "Money Borrowed"}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.82),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Edit button
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _openAddEditSheet(context, existingDebt: debt);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.22),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.edit_outlined,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Delete button
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _confirmDelete(context, debt);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFFF8A80),
                                      size: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Close button
                                GestureDetector(
                                  onTap: () => Navigator.pop(ctx),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.22),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Contact Hero Pill (Avatar + Name + Direction tag + Urgency)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Initials Avatar
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isLend
                                        ? const [Color(0xFF69F0AE), Color(0xFF10B981)]
                                        : const [Color(0xFFFFAB91), Color(0xFFFF5722)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isLend
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFFF5722))
                                          .withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    initials,
                                    style: TextStyle(
                                      color: isLend ? const Color(0xFF0F3632) : Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      debt.personName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isLend
                                              ? Icons.arrow_outward_rounded
                                              : Icons.arrow_downward_rounded,
                                          size: 13,
                                          color: isLend
                                              ? const Color(0xFF69F0AE)
                                              : const Color(0xFFFF8A80),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            isLend
                                                ? 'You Lent (To Receive)'
                                                : 'You Borrowed (To Pay)',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: isLend
                                                  ? const Color(0xFF69F0AE)
                                                  : const Color(0xFFFF8A80),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildUrgencyPill(context, debt),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Amount Block
                        Text(
                          debt.isRepaid
                              ? 'Fully Settled'
                              : (debt.hasPartialSettlements
                                  ? 'Remaining Balance'
                                  : (isLend ? 'Amount to Receive' : 'Amount to Repay')),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.75),
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                debt.isRepaid ? '₹0' : _formatAmount(debt.amount),
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: debt.isRepaid
                                      ? const Color(0xFF69F0AE)
                                      : (isLend ? const Color(0xFF69F0AE) : const Color(0xFFFF8A80)),
                                  letterSpacing: -1,
                                ),
                              ),
                              if (debt.hasPartialSettlements && !debt.isRepaid) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'of ${_formatAmount(debt.originalAmount)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Status Pill (Frosted Capsule)
                        _buildStatusBadge(context, debt),

                        // Progress Bar if partial or settled
                        if (debt.hasPartialSettlements || debt.isRepaid) ...[
                          const SizedBox(height: 14),
                          Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Paid: ${_formatAmount(debt.totalPaid)} (${(debt.progressPercent * 100).toInt()}%)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF69F0AE),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    debt.isRepaid
                                        ? '100% Repaid'
                                        : 'Left: ${_formatAmount(debt.amount)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.75),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: debt.isRepaid ? 1.0 : debt.progressPercent.clamp(0.0, 1.0),
                                  minHeight: 7,
                                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    debt.isRepaid
                                        ? const Color(0xFF69F0AE)
                                        : (isLend ? const Color(0xFF69F0AE) : const Color(0xFFFF8A80)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 16),

                        // ─── 2. Dates & Timeline Info Grid (Inside the Top Container!) ───
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildMetaItem(
                                      context,
                                      icon: Icons.calendar_today_rounded,
                                      iconColor: isLend
                                          ? const Color(0xFF69F0AE)
                                          : const Color(0xFF80CBC4),
                                      label: 'Date Initiated',
                                      value: DateFormat('dd MMM yyyy').format(debt.date),
                                      subvalue: DateFormat('EEEE').format(debt.date),
                                      isHeaderStyle: true,
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 44,
                                    color: Colors.white.withValues(alpha: 0.20),
                                    margin: const EdgeInsets.symmetric(horizontal: 10),
                                  ),
                                  Expanded(
                                    child: _buildMetaItem(
                                      context,
                                      icon: Icons.event_available_rounded,
                                      iconColor: debt.isOverdue
                                          ? const Color(0xFFFF8A80)
                                          : (debt.isDueToday
                                              ? const Color(0xFFFFD54F)
                                              : (isLend
                                                  ? const Color(0xFF69F0AE)
                                                  : const Color(0xFF80CBC4))),
                                      label: 'Repayment Date',
                                      value: DateFormat('dd MMM yyyy').format(debt.dueDate),
                                      subvalue: debt.isRepaid
                                          ? (debt.repaidDate != null
                                              ? 'Repaid ${DateFormat('dd MMM').format(debt.repaidDate!)}'
                                              : 'Settled')
                                          : (debt.isDueToday
                                              ? 'Due today'
                                              : (debt.isOverdue
                                                  ? '${debt.daysDifference.abs()}d overdue'
                                                  : 'In ${debt.daysDifference} days')),
                                      isHeaderStyle: true,
                                    ),
                                  ),
                                ],
                              ),
                              if (debt.remindOnDueDate) ...[
                                const SizedBox(height: 10),
                                Divider(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  height: 1,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.notifications_active_rounded,
                                      size: 15,
                                      color: Color(0xFF69F0AE),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Due date push notification reminder is active',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white.withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── Lower Section (Note, History, Actions) ───
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Note Bubble
                        if (debt.note != null && debt.note!.trim().isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.borderOf(context).withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.format_quote_rounded,
                                  size: 18,
                                  color: AppColors.textLightOf(context),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Note',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textLightOf(context),
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        debt.note!.trim(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.35,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimaryOf(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Settlement History Timeline
                        if (debt.settlements.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.borderOf(context).withValues(alpha: 0.6),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.history_rounded,
                                          size: 17,
                                          color: AppColors.income,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Settlement History (${debt.settlements.length})',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimaryOf(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.income.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Total: +${_formatAmount(debt.totalSettled)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.income,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ...debt.settlements.asMap().entries.map((entry) {
                                  final idx = entry.key + 1;
                                  final s = entry.value;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AppColors.cardOf(context),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.borderOf(context).withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: AppColors.income.withValues(alpha: 0.14),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              '$idx',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.income,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                DateFormat('dd MMMM yyyy').format(s.date),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textPrimaryOf(context),
                                                ),
                                              ),
                                              if (s.note != null && s.note!.trim().isNotEmpty)
                                                Text(
                                                  s.note!.trim(),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.textSecondaryOf(context),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '+${_formatAmount(s.amount)}',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.income,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],

                        // Action Buttons
                        if (!debt.isRepaid) ...[
                          // Primary Settle / Partial repayment button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showPartialSettleSheet(context, debt);
                              },
                              icon: const Icon(Icons.check_circle_rounded, size: 20),
                              label: Text(
                                isLend ? 'Record Settlement' : 'Record Repayment',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),

                          // Compact WhatsApp reminder button for Lent debts
                          if (isLend) ...[
                            const SizedBox(height: 10),
                            Center(
                              child: InkWell(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _sendReminder(debt);
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366).withValues(alpha: isDark ? 0.16 : 0.08),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFF25D366).withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        size: 15,
                                        color: Color(0xFF25D366),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Send WhatsApp Reminder',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ] else ...[
                          // Reopen button for settled debts
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _toggleSettled(debt);
                              },
                              icon: const Icon(Icons.restart_alt_rounded, size: 18),
                              label: const Text(
                                'Reopen as Pending Due',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimaryOf(context),
                                side: BorderSide(
                                  color: AppColors.borderOf(context),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

  Widget _buildUrgencyPill(BuildContext context, DebtModel debt) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    if (debt.isUrgent) {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.22);
      fg = const Color(0xFFFF8A80);
      label = 'Strict';
      icon = Icons.bolt_rounded;
    } else if (debt.isLenient) {
      bg = const Color(0xFF10B981).withValues(alpha: 0.22);
      fg = const Color(0xFF69F0AE);
      label = 'Flexible';
      icon = Icons.spa_rounded;
    } else {
      bg = const Color(0xFFF59E0B).withValues(alpha: 0.22);
      fg = const Color(0xFFFFD54F);
      label = 'Normal';
      icon = Icons.schedule_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, DebtModel debt) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    if (debt.isRepaid) {
      bg = const Color(0xFF10B981).withValues(alpha: 0.22);
      fg = const Color(0xFF69F0AE);
      label = debt.isRepaidOnTime
          ? 'Paid on time'
          : (debt.isRepaidLate ? 'Paid ${debt.daysLateRepaid}d late' : 'Settled');
      icon = Icons.check_circle_rounded;
    } else if (debt.isDueToday) {
      bg = const Color(0xFFF59E0B).withValues(alpha: 0.22);
      fg = const Color(0xFFFFD54F);
      label = 'Due Today';
      icon = Icons.access_time_filled_rounded;
    } else if (debt.isOverdue) {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.22);
      fg = const Color(0xFFFF8A80);
      label = 'Overdue by ${debt.daysDifference.abs()} days';
      icon = Icons.warning_rounded;
    } else {
      bg = Colors.white.withValues(alpha: 0.16);
      fg = Colors.white;
      label = 'Pending • Due in ${debt.daysDifference} days';
      icon = Icons.timelapse_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    String? subvalue,
    bool isHeaderStyle = false,
  }) {
    final labelColor = isHeaderStyle
        ? Colors.white.withValues(alpha: 0.70)
        : AppColors.textLightOf(context);
    final valueColor = isHeaderStyle
        ? Colors.white
        : AppColors.textPrimaryOf(context);
    final subvalueColor = isHeaderStyle
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textSecondaryOf(context);
    final iconBgColor = isHeaderStyle
        ? iconColor.withValues(alpha: 0.20)
        : iconColor.withValues(alpha: 0.12);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(10),
            border: isHeaderStyle
                ? Border.all(color: iconColor.withValues(alpha: 0.35), width: 0.8)
                : null,
          ),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
              if (subvalue != null) ...[
                const SizedBox(height: 1),
                Text(
                  subvalue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isHeaderStyle ? FontWeight.w500 : FontWeight.normal,
                    color: subvalueColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ─── CONFIRM DELETE ───
  Future<void> _confirmDelete(BuildContext context, DebtModel debt) async {
    bool deleteLinked = true;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardOf(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                'Delete Record?',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete this debt record for ${debt.personName} (${_formatAmount(debt.amount)})?',
                    style: TextStyle(color: AppColors.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: 12),
                  if (debt.transactionId != null)
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: CheckboxListTile(
                        value: deleteLinked,
                        onChanged: (val) =>
                            setDialogState(() => deleteLinked = val ?? true),
                        activeColor: AppColors.error,
                        dense: true,
                        title: const Text(
                          'Also delete associated Expense/Income transaction',
                          style: TextStyle(fontSize: 11),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondaryOf(context)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _debtService.deleteDebt(
                      debt,
                      deleteLinkedTransactions: deleteLinked,
                    );
                    if (mounted) {
                      AppSnackbar.showSuccess(this.context, 'Record deleted');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── ADD / EDIT BOTTOM SHEET ───
  void _openAddEditSheet(
    BuildContext context, {
    DebtModel? existingDebt,
    int initialType = 0, // 0=Lend, 1=Borrow
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _AddEditDebtSheet(
          existingDebt: existingDebt,
          initialType: initialType,
          allDebts: _cachedDebts,
          onSaved: () {},
        );
      },
    );
  }
}

// ─── ADD / EDIT SHEET WIDGET ───
class _AddEditDebtSheet extends StatefulWidget {
  final DebtModel? existingDebt;
  final int initialType; // 0=Lend, 1=Borrow
  final List<DebtModel> allDebts;
  final VoidCallback onSaved;

  const _AddEditDebtSheet({
    this.existingDebt,
    this.initialType = 0,
    this.allDebts = const [],
    required this.onSaved,
  });

  @override
  State<_AddEditDebtSheet> createState() => _AddEditDebtSheetState();
}

class _AddEditDebtSheetState extends State<_AddEditDebtSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _personController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  late int _typeIndex; // 0 = Lent, 1 = Borrowed
  late final AnimationController _sliderAnimController;
  String _urgency = 'medium'; // 'low', 'medium', 'high'
  DateTime _loanDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  bool _remindOnDueDate = true;
  bool _isSaving = false;

  bool get isEditing => widget.existingDebt != null;

  @override
  void initState() {
    super.initState();
    _typeIndex = widget.initialType;
    if (isEditing) {
      final d = widget.existingDebt!;
      _typeIndex = d.isLend ? 0 : 1;
      _urgency = d.urgency;
      _amountController.text =
          d.amount.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');
      _personController.text = d.personName;
      _noteController.text = d.note ?? '';
      _loanDate = d.date;
      _dueDate = d.dueDate;
      _remindOnDueDate = d.remindOnDueDate;
    }
    _sliderAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: _typeIndex.toDouble(),
    );
  }

  @override
  void dispose() {
    _sliderAnimController.dispose();
    _amountController.dispose();
    _personController.dispose();
    _noteController.dispose();
    _noteFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setSliderIndex(int idx) {
    if (_typeIndex == idx && _sliderAnimController.value == idx.toDouble()) return;
    HapticFeedback.selectionClick();
    setState(() => _typeIndex = idx);
    _sliderAnimController.animateTo(
      idx.toDouble(),
      curve: Curves.easeOutCubic,
    );
  }

  Map<String, int> get _contactFrequencies {
    final Map<String, int> freq = {};
    for (final d in widget.allDebts) {
      final name = d.personName.trim();
      if (name.isNotEmpty) {
        freq[name] = (freq[name] ?? 0) + 1;
      }
    }
    return freq;
  }

  List<String> get _sortedContacts {
    final freq = _contactFrequencies;
    final list = freq.keys.toList();
    list.sort((a, b) {
      final c = (freq[b] ?? 0).compareTo(freq[a] ?? 0);
      if (c != 0) return c;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return list;
  }

  List<String> get _matchingContacts {
    final query = _personController.text.trim().toLowerCase();
    final all = _sortedContacts;
    if (query.isEmpty) {
      return all.take(3).toList();
    }
    return all
        .where((name) => name.toLowerCase().contains(query))
        .take(4)
        .toList();
  }

  void _showAllContactsModal(BuildContext context) {
    final contacts = _sortedContacts;
    final freqs = _contactFrequencies;
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final filtered = contacts.where((name) {
              return name
                  .toLowerCase()
                  .contains(searchQuery.toLowerCase().trim());
            }).toList();

            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final isLend = _typeIndex == 0;
            final activeColor =
                isLend ? AppColors.income : const Color(0xFFE65100);

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.58,
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.of(ctx).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardOf(ctx),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderOf(ctx),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Past Contact',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimaryOf(ctx),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceOf(ctx),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppColors.textSecondaryOf(ctx),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Search Bar
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(ctx),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.borderOf(ctx).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 16,
                          color: AppColors.textSecondaryOf(ctx),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            style: TextStyle(
                              fontSize: 13.5,
                              color: AppColors.textPrimaryOf(ctx),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search contact name...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: AppColors.textLightOf(ctx),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (val) {
                              setModalState(() => searchQuery = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No contacts found',
                              style: TextStyle(
                                color: AppColors.textLightOf(ctx),
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: AppColors.borderOf(ctx)
                                  .withValues(alpha: 0.3),
                            ),
                            itemBuilder: (context, idx) {
                              final name = filtered[idx];
                              final count = freqs[name] ?? 1;
                              final isSelected =
                                  _personController.text.trim().toLowerCase() ==
                                      name.toLowerCase();

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 0),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor:
                                      activeColor.withValues(alpha: 0.14),
                                  child: Text(
                                    _getPersonInitials(name),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: activeColor,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    fontSize: 13.5,
                                    color: isSelected
                                        ? activeColor
                                        : AppColors.textPrimaryOf(ctx),
                                  ),
                                ),
                                subtitle: Text(
                                  '$count due record${count > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryOf(ctx),
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: activeColor,
                                        size: 18,
                                      )
                                    : null,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _personController.text = name);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickDate(bool isDueDate) async {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLend = _typeIndex == 0;
    final initial = isDueDate ? _dueDate : _loanDate;
    DateTime temp = initial;

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext ctx) {
        return Material(
          type: MaterialType.transparency,
          child: Container(
            height: 280,
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              decoration: TextDecoration.none,
                              color: AppColors.textSecondaryOf(context),
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          isDueDate
                              ? 'Repayment Date'
                              : (isLend ? 'Lent Date' : 'Borrowed Date'),
                          style: TextStyle(
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            setState(() {
                              if (isDueDate) {
                                _dueDate = temp;
                              } else {
                                _loanDate = temp;
                              }
                            });
                            HapticFeedback.selectionClick();
                          },
                          child: Text(
                            'Done',
                            style: TextStyle(
                              decoration: TextDecoration.none,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: _typeIndex == 0
                                  ? AppColors.income
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: isDark ? Brightness.dark : Brightness.light,
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(
                          decoration: TextDecoration.none,
                          color: AppColors.textPrimaryOf(context),
                          fontSize: 19,
                        ),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: initial,
                      minimumDate: DateTime(2020),
                      maximumDate: DateTime(2035),
                      onDateTimeChanged: (DateTime newDate) {
                        temp = newDate;
                        HapticFeedback.selectionClick();
                      },
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

  void _setQuickDueDate(int days) {
    HapticFeedback.selectionClick();
    setState(() {
      _dueDate = DateTime.now().add(Duration(days: days));
    });
  }

  bool _isQuickDateSelected(int days) {
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day + days);
    final due = DateTime(_dueDate.year, _dueDate.month, _dueDate.day);
    return due.difference(target).inDays == 0;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'Please enter a valid amount');
      return;
    }

    final personName = _personController.text.trim();
    if (personName.isEmpty) {
      AppSnackbar.showError(context, 'Please enter contact name');
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final type = _typeIndex == 0 ? 'lend' : 'borrow';
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      if (isEditing) {
        final updated = widget.existingDebt!.copyWith(
          type: type,
          personName: personName,
          amount: amount,
          date: _loanDate,
          dueDate: _dueDate,
          note: note,
          remindOnDueDate: _remindOnDueDate,
          urgency: _urgency,
        );
        await DebtService.instance.updateDebt(updated);
      } else {
        final newDebt = DebtModel(
          type: type,
          personName: personName,
          amount: amount,
          date: _loanDate,
          dueDate: _dueDate,
          note: note,
          remindOnDueDate: _remindOnDueDate,
          urgency: _urgency,
        );
        await DebtService.instance.addDebt(newDebt);
      }

      widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context);

      final isOnline = NetworkHelper.isOnline.value;
      AppSnackbar.showSuccess(
        context,
        !isOnline
            ? (isEditing
                ? 'Record updated locally! (Will sync when online)'
                : 'Record saved locally! (Will sync when online)')
            : (isEditing
                ? 'Record updated!'
                : (_typeIndex == 0
                    ? 'Lent record saved!'
                    : 'Borrow record saved!')),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _getPersonInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }

  Widget _buildSlidableTypeBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(3.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final pillWidth = (totalWidth - 2) / 2;

          return AnimatedBuilder(
            animation: _sliderAnimController,
            builder: (context, _) {
              final double t = _sliderAnimController.value.clamp(0.0, 1.0);
              final double leftOffset = t * pillWidth;

              final Color c1 = Color.lerp(
                const Color(0xFF10B981),
                const Color(0xFFFF7043),
                t,
              )!;
              final Color c2 = Color.lerp(
                const Color(0xFF059669),
                const Color(0xFFE64A19),
                t,
              )!;
              final Color borderC = Color.lerp(
                const Color(0xFF10B981).withValues(alpha: 0.70),
                const Color(0xFFFF7043).withValues(alpha: 0.70),
                t,
              )!;
              final Color glowC = Color.lerp(
                const Color(0xFF10B981).withValues(alpha: 0.35),
                const Color(0xFFE64A19).withValues(alpha: 0.35),
                t,
              )!;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  final double delta = details.delta.dx / pillWidth;
                  _sliderAnimController.value =
                      (_sliderAnimController.value + delta).clamp(0.0, 1.0);
                  final int nearest = _sliderAnimController.value.round();
                  if (nearest != _typeIndex) {
                    setState(() => _typeIndex = nearest);
                    HapticFeedback.selectionClick();
                  }
                },
                onHorizontalDragEnd: (details) {
                  final double v = details.primaryVelocity ?? 0;
                  int target = _sliderAnimController.value.round();
                  if (v > 200) target = 1;
                  if (v < -200) target = 0;
                  _setSliderIndex(target);
                },
                child: SizedBox(
                  height: 42,
                  child: Stack(
                    children: [
                      Positioned(
                        left: leftOffset,
                        width: pillWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [c1, c2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: borderC, width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: glowC,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _setSliderIndex(0),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.north_east_rounded,
                                      size: 14,
                                      color: Color.lerp(
                                        Colors.white,
                                        Colors.white.withValues(alpha: 0.65),
                                        t,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Lent',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: t < 0.5
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: Color.lerp(
                                          Colors.white,
                                          Colors.white.withValues(alpha: 0.65),
                                          t,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _setSliderIndex(1),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.south_west_rounded,
                                      size: 14,
                                      color: Color.lerp(
                                        Colors.white.withValues(alpha: 0.65),
                                        Colors.white,
                                        t,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Borrowed',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: t >= 0.5
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: Color.lerp(
                                          Colors.white.withValues(alpha: 0.65),
                                          Colors.white,
                                          t,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLend = _typeIndex == 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentGreen = Color(0xFF10B981);
    const accentCoral = Color(0xFFE65100);
    final themeAccent = isLend ? accentGreen : accentCoral;
    final primaryBtnColor =
        isLend ? const Color(0xFF10B981) : const Color(0xFFE65100);

    final sortedContacts = _sortedContacts;
    final matchingContacts = _matchingContacts;
    final hasMoreContacts = sortedContacts.length > 3 &&
        _personController.text.trim().isEmpty;
    final moreCount = sortedContacts.length - 3;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) {
          const double dragSensitivity = 180.0;
          final double delta = details.delta.dx / dragSensitivity;
          _sliderAnimController.value =
              (_sliderAnimController.value + delta).clamp(0.0, 1.0);
          final int nearest = _sliderAnimController.value.round();
          if (nearest != _typeIndex) {
            setState(() => _typeIndex = nearest);
            HapticFeedback.selectionClick();
          }
        },
        onHorizontalDragEnd: (details) {
          final double v = details.primaryVelocity ?? 0;
          int target = _sliderAnimController.value.round();
          if (v > 200) target = 1;
          if (v < -200) target = 0;
          _setSliderIndex(target);
        },
        child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Hero Header in Signature Emerald/Teal Theme ──
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [
                          Color(0xFF0F2624),
                          Color(0xFF163E3B),
                          Color(0xFF1E5D57),
                        ]
                      : const [
                          Color(0xFF0F3632),
                          Color(0xFF1E5D57),
                          Color(0xFF2C7A72),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                  bottom: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Frosted Drag Handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Title & Close Button Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEditing
                                  ? 'Edit Due Record'
                                  : (isLend ? 'New Lent Record' : 'New Borrow Record'),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isLend
                                  ? 'Record money you gave to collect later'
                                  : 'Record money you borrowed to repay later',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Slidable Segmented Bar (Lent | Borrowed) in Hero Header
                  _buildSlidableTypeBar(),
                ],
              ),
            ),

            // ─── Continuous Scrollable Body ───
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Amount Input Card
                    Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context)
                              .withValues(alpha: 0.8),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '₹',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: themeAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimaryOf(context),
                                letterSpacing: -0.3,
                              ),
                              cursorColor: themeAccent,
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  color: AppColors.textLightOf(context),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter amount';
                                }
                                if (double.tryParse(val.trim()) == null) {
                                  return 'Enter valid number';
                                }
                                return null;
                              },
                            ),
                          ),
                          if (_amountController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _amountController.clear());
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppColors.borderOf(context)
                                      .withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.borderOf(context)
                                    .withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Amount',
                                style: TextStyle(
                                  color: AppColors.textSecondaryOf(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Name Input Card
                    Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context)
                              .withValues(alpha: 0.8),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isLend
                                    ? const [
                                        Color(0xFF69F0AE),
                                        Color(0xFF10B981)
                                      ]
                                    : const [
                                        Color(0xFFFFAB91),
                                        Color(0xFFFF5722)
                                      ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _getPersonInitials(_personController.text),
                                style: TextStyle(
                                  color: isLend
                                      ? const Color(0xFF0F3632)
                                      : Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _personController,
                              textCapitalization: TextCapitalization.words,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              cursorColor: themeAccent,
                              decoration: InputDecoration(
                                hintText: isLend
                                    ? 'Friend or Contact name'
                                    : 'Lender or Contact name',
                                hintStyle: TextStyle(
                                  color: AppColors.textLightOf(context),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Contact name is required';
                                }
                                return null;
                              },
                            ),
                          ),
                          if (_personController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _personController.clear());
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.borderOf(context)
                                      .withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ),
                          if (sortedContacts.isNotEmpty)
                            GestureDetector(
                              onTap: () => _showAllContactsModal(context),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: themeAccent.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.contacts_rounded,
                                  size: 16,
                                  color: themeAccent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Refined Contact Suggestions Row
                    if (matchingContacts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 13,
                            color: AppColors.textLightOf(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _personController.text.trim().isEmpty
                                ? 'Recent:'
                                : 'Suggestions:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SizedBox(
                              height: 28,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: matchingContacts.length +
                                    (hasMoreContacts ? 1 : 0),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 6),
                                itemBuilder: (context, idx) {
                                  if (idx == matchingContacts.length) {
                                    // "+X more ▾" button
                                    return GestureDetector(
                                      onTap: () =>
                                          _showAllContactsModal(context),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceOf(context),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: AppColors.borderOf(context)
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '+$moreCount more',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: themeAccent,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.arrow_drop_down_rounded,
                                              size: 14,
                                              color: themeAccent,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  final name = matchingContacts[idx];
                                  final isSelected = _personController.text
                                          .trim()
                                          .toLowerCase() ==
                                      name.toLowerCase();

                                  return GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(
                                          () => _personController.text = name);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? themeAccent
                                                .withValues(alpha: 0.15)
                                            : AppColors.surfaceOf(context),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? themeAccent
                                              : AppColors.borderOf(context)
                                                  .withValues(alpha: 0.7),
                                          width: isSelected ? 1.4 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 8,
                                            backgroundColor: themeAccent
                                                .withValues(alpha: 0.2),
                                            child: Text(
                                              _getPersonInitials(name),
                                              style: TextStyle(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w800,
                                                color: themeAccent,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              color: isSelected
                                                  ? themeAccent
                                                  : AppColors.textPrimaryOf(
                                                      context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Refined Repayment Timeline Card
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.borderOf(context)
                              .withValues(alpha: 0.8),
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    size: 15,
                                    color: themeAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Repayment Timeline',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: themeAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _dueDate.isBefore(DateTime.now())
                                      ? 'Overdue'
                                      : '${_dueDate.difference(DateTime.now()).inDays + 1}d remaining',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: themeAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // 2 Milestone Tiles (Lent/Borrowed Date + Repayment Date)
                          Row(
                            children: [
                              // Lent / Borrowed Date Tile (replaces "Initiated")
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _pickDate(false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.cardOf(context),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.borderOf(context)
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isLend
                                              ? 'Lent Date'
                                              : 'Borrowed Date',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textSecondaryOf(
                                                context),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat('dd MMM yyyy')
                                              .format(_loanDate),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textPrimaryOf(
                                                context),
                                          ),
                                        ),
                                        Text(
                                          DateFormat('EEEE').format(_loanDate),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color:
                                                AppColors.textLightOf(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 15,
                                  color: AppColors.textLightOf(context),
                                ),
                              ),
                              // Repayment Date Tile
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _pickDate(true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.cardOf(context),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: themeAccent
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Repayment Date',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: themeAccent,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat('dd MMM yyyy')
                                              .format(_dueDate),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textPrimaryOf(
                                                context),
                                          ),
                                        ),
                                        Text(
                                          'In ${_dueDate.difference(DateTime.now()).inDays + 1} days',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: themeAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Refined Days / Week Quick Options
                          Row(
                            children: [
                              _buildQuickDateChip('+3 Days', 3, isLend),
                              const SizedBox(width: 6),
                              _buildQuickDateChip('+1 Week', 7, isLend),
                              const SizedBox(width: 6),
                              _buildQuickDateChip('+2 Weeks', 14, isLend),
                              const SizedBox(width: 6),
                              _buildQuickDateChip('+1 Month', 30, isLend),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Urgency Options (Flexible, Normal, Strict)
                    Row(
                      children: [
                        _buildUrgencyOption(
                          value: 'low',
                          label: 'Flexible',
                          color: const Color(0xFF10B981),
                          icon: Icons.spa_rounded,
                        ),
                        const SizedBox(width: 6),
                        _buildUrgencyOption(
                          value: 'medium',
                          label: 'Normal',
                          color: const Color(0xFFF59E0B),
                          icon: Icons.schedule_rounded,
                        ),
                        const SizedBox(width: 6),
                        _buildUrgencyOption(
                          value: 'high',
                          label: 'Strict',
                          color: const Color(0xFFEF4444),
                          icon: Icons.bolt_rounded,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Note Field
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context)
                              .withValues(alpha: 0.8),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.format_quote_rounded,
                            size: 16,
                            color: AppColors.textLightOf(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _noteController,
                              focusNode: _noteFocusNode,
                              scrollPadding:
                                  const EdgeInsets.only(bottom: 40),
                              style: TextStyle(
                                fontSize: 13.5,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Note or reason (optional)',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textLightOf(context),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Remind on Repayment Day Switch
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context)
                              .withValues(alpha: 0.8),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.notifications_active_rounded,
                                size: 15,
                                color: themeAccent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Remind on repayment day',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                            ],
                          ),
                          Transform.scale(
                            scale: 0.82,
                            child: Switch(
                              value: _remindOnDueDate,
                              onChanged: (val) =>
                                  setState(() => _remindOnDueDate = val),
                              activeTrackColor: themeAccent,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ─── Save Button (Inside scrollable content) ───
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox.shrink()
                            : const Icon(Icons.check_circle_rounded, size: 18),
                        label: _isSaving
                            ? const BuddyLoadingIndicator(size: 22)
                            : Text(
                                isEditing
                                    ? 'Update Record'
                                    : (isLend
                                        ? 'Save Lent Record'
                                        : 'Save Borrow Record'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                ),
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBtnColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
          const _KeyboardSpacer(),
        ],
      ),
    ),
  ),
);
}

  Widget _buildQuickDateChip(String label, int days, bool isLend) {
    final isSelected = _isQuickDateSelected(days);
    final activeColor = isLend ? AppColors.income : const Color(0xFFE65100);

    return Expanded(
      child: GestureDetector(
        onTap: () => _setQuickDueDate(days),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.15)
                : AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : AppColors.borderOf(context).withValues(alpha: 0.6),
              width: isSelected ? 1.4 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? activeColor
                    : AppColors.textSecondaryOf(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUrgencyOption({
    required String value,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = _urgency == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _urgency = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.14)
                : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color
                  : AppColors.borderOf(context).withValues(alpha: 0.6),
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? color : AppColors.textSecondaryOf(context),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? color : AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── KEYBOARD SPACER (Isolates insets listener from main sheet) ───
class _KeyboardSpacer extends StatelessWidget {
  const _KeyboardSpacer();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final targetHeight = bottomInset > 0 ? bottomInset : bottomPadding;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: targetHeight,
    );
  }
}

