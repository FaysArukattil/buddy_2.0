// lib/views/screens/bottomnavbarscreen/borrow_lend_screen.dart
import 'package:flutter/material.dart';
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
  List<String> _recentContacts = [];
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
      HapticFeedback.selectionClick();
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
      );
    }
  }

  void _onToggleStatus(int mode, {bool isUserAction = true}) {
    final double currentVal = _statusFilterAnimController.value;
    final bool alreadyThere = (currentVal - mode).abs() < 0.01;
    if (_statusFilter == mode && alreadyThere) return;
    if (isUserAction) {
      HapticFeedback.selectionClick();
    }
    if (_statusFilter != mode) {
      setState(() => _statusFilter = mode);
    }
    _statusFilterAnimController.animateTo(
      mode.toDouble(),
      duration: Duration(milliseconds: isUserAction ? 260 : 360),
      curve: Curves.easeOutCubic,
    );
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
            final contacts = <String>{};
            for (final d in _cachedDebts) {
              if (d.personName.trim().isNotEmpty) {
                contacts.add(d.personName.trim());
              }
            }
            _recentContacts = contacts.toList();
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
      },
      onHorizontalDragUpdate: (details) {
        _headerDragAccumX += details.delta.dx;
        final double w = (_typeFilterPageController.hasClients &&
                _typeFilterPageController.positions.length == 1 &&
                _typeFilterPageController.position.haveDimensions)
            ? _typeFilterPageController.position.viewportDimension
            : MediaQuery.of(context).size.width;
        final double deltaPages =
            -_headerDragAccumX / (w > 0 ? w : 300.0);
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
          HapticFeedback.selectionClick();
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
        if (velocity < -250) {
          target = (currentP.floor() + 1).clamp(0, 2);
        } else if (velocity > 250) {
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
                    HapticFeedback.selectionClick();
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
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
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
              padding: EdgeInsets.fromLTRB(
                22,
                12,
                22,
                MediaQuery.of(ctx).padding.bottom + 20,
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
                  const SizedBox(height: 18),

                  // Icon badge
                  Container(
                    width: 54,
                    height: 54,
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
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Title & Subtitle
                  Text(
                    'Keep Dues Separate?',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose if personal borrow & lend money changes your main wallet balance.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Interactive Switch Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          padding: const EdgeInsets.all(8),
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
                            size: 20,
                            color: _isSeparate
                                ? AppColors.primary
                                : AppColors.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Keep Separate',
                                style: TextStyle(
                                  fontSize: 14,
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
                                  fontSize: 11.5,
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

                  const SizedBox(height: 14),

                  // Explanatory points in plain English
                  Container(
                    padding: const EdgeInsets.all(14),
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
                        const SizedBox(height: 12),
                        _buildInfoBullet(
                          icon: Icons.visibility_off_outlined,
                          iconColor: AppColors.expense,
                          title: 'When ON (Separate)',
                          desc:
                              'Borrow & Lend stays only in this tab. Your main wallet balance and statistics will ignore your friend dues completely.',
                        ),
                        const SizedBox(height: 12),
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
                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
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
                    HapticFeedback.selectionClick();
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

                      // Bottom Action Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
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
                                const SizedBox(width: 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Signature Curved Gradient Header Banner ──
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
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Column(
                        children: [
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
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.payments_rounded,
                                  color: Colors.white,
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
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    Text(
                                      '${debt.personName} • Remaining: ${_formatAmount(totalAmount)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.78),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
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
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
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
                  ],
                ),
              ),
            ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Signature Curved Gradient Header Banner ──
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
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  children: [
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Debt Record Details',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${debt.personName} • ${debt.isLend ? "You Lent" : "You Borrowed"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                _openAddEditSheet(context, existingDebt: debt);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(7),
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
                                  size: 17,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                _confirmDelete(context, debt);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.40),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFFF8A80),
                                  size: 17,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                padding: const EdgeInsets.all(7),
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
                                  size: 17,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              _buildDetailRow(
                context,
                'Person',
                debt.personName,
                Icons.person_outline,
              ),
              _buildDetailRow(
                context,
                'Type',
                debt.isLend ? 'Lent (You gave money)' : 'Borrowed (You took money)',
                debt.isLend ? Icons.arrow_outward_rounded : Icons.arrow_downward_rounded,
                valueColor: debt.isLend ? AppColors.income : AppColors.expense,
              ),
              _buildDetailRow(
                context,
                'Initial Amount',
                '${debt.isLend ? '+' : '-'}${_formatAmount(debt.originalAmount)}',
                Icons.currency_rupee_rounded,
                valueColor: debt.isLend ? AppColors.income : AppColors.expense,
              ),
              if (debt.hasPartialSettlements || debt.isRepaid) ...[
                _buildDetailRow(
                  context,
                  'Total Paid',
                  '${_formatAmount(debt.totalPaid)} (${(debt.progressPercent * 100).toInt()}%)',
                  Icons.task_alt_rounded,
                  valueColor: AppColors.income,
                ),
                _buildDetailRow(
                  context,
                  'Remaining Balance',
                  debt.isRepaid
                      ? '₹0 (Fully Settled)'
                      : '${debt.isLend ? '+' : '-'}${_formatAmount(debt.amount)}',
                  Icons.account_balance_wallet_outlined,
                  valueColor: debt.isRepaid
                      ? AppColors.income
                      : (debt.isLend ? AppColors.income : AppColors.expense),
                ),
              ],
              _buildDetailRow(
                context,
                'Date Initiated',
                DateFormat('EEEE, dd MMMM yyyy').format(debt.date),
                Icons.calendar_today_outlined,
              ),
              _buildDetailRow(
                context,
                'Repayment Expected',
                DateFormat('EEEE, dd MMMM yyyy').format(debt.dueDate),
                Icons.event_outlined,
              ),
              _buildDetailRow(
                context,
                'Repayment Urgency',
                debt.isUrgent
                    ? '🔴 Strict (Urgent / Expected on date)'
                    : (debt.isLenient
                        ? '🟢 Lenient (Flexible / No rush)'
                        : '🟡 Normal (Standard due date)'),
                Icons.bolt_rounded,
                valueColor: debt.urgencyColor,
              ),
              _buildDetailRow(
                context,
                'Status',
                debt.isRepaid
                    ? (debt.isRepaidOnTime
                        ? '✅ Paid on time (${debt.repaidDate != null ? DateFormat('dd MMM yyyy').format(debt.repaidDate!) : "Settled"})'
                        : (debt.isRepaidLate
                            ? '⚠️ Paid ${debt.daysLateRepaid}d late (${debt.repaidDate != null ? DateFormat('dd MMM yyyy').format(debt.repaidDate!) : "Settled"})'
                            : '✅ Settled'))
                    : (debt.isDueToday
                        ? '⏰ Due Today!'
                        : (debt.isOverdue
                            ? '⚠️ Overdue by ${debt.daysDifference.abs()} days'
                            : 'Pending (Due in ${debt.daysDifference} days)')),
                Icons.info_outline,
                valueColor: debt.isRepaid
                    ? (debt.isRepaidOnTime ? AppColors.income : const Color(0xFFFF9800))
                    : (debt.isOverdue
                        ? AppColors.expense
                        : (debt.isDueToday ? const Color(0xFFFF9800) : const Color(0xFF00897B))),
              ),
              if (debt.note != null && debt.note!.isNotEmpty)
                _buildDetailRow(
                  context,
                  'Note',
                  debt.note!,
                  Icons.notes_rounded,
                ),

              // Settlement History Timeline
              if (debt.settlements.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceOf(context),
                    borderRadius: BorderRadius.circular(14),
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
                          Row(
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 16,
                                color: AppColors.textSecondaryOf(context),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Settlement History (${debt.settlements.length})',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Paid: ${_formatAmount(debt.totalSettled)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: debt.isLend ? AppColors.income : AppColors.expense,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...debt.settlements.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final s = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.cardOf(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.borderOf(context).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: (debt.isLend
                                            ? AppColors.income
                                            : AppColors.expense)
                                        .withValues(alpha: 0.15),
                                    child: Text(
                                      '$idx',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: debt.isLend
                                            ? AppColors.income
                                            : AppColors.expense,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('dd MMMM yyyy').format(s.date),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimaryOf(context),
                                        ),
                                      ),
                                      if (s.note != null && s.note!.trim().isNotEmpty)
                                        Text(
                                          s.note!.trim(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textLightOf(context),
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                '+${_formatAmount(s.amount)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: debt.isLend
                                      ? AppColors.income
                                      : AppColors.expense,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Action buttons in detail modal
              if (!debt.isRepaid) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showPartialSettleSheet(context, debt);
                    },
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: Text(
                      debt.isLend ? 'Settle / Partial Repayment' : 'Record Repayment',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          debt.isLend ? AppColors.income : AppColors.expense,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              if (debt.isLend && !debt.isRepaid)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _sendReminder(debt);
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: const Text('Send Reminder Message'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
},
);
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textLightOf(context)),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
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
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: _AddEditDebtSheet(
            existingDebt: existingDebt,
            initialType: initialType,
            recentContacts: _recentContacts,
            onSaved: () {},
          ),
        );
      },
    );
  }
}

// ─── ADD / EDIT SHEET WIDGET ───
class _AddEditDebtSheet extends StatefulWidget {
  final DebtModel? existingDebt;
  final int initialType; // 0=Lend, 1=Borrow
  final List<String> recentContacts;
  final VoidCallback onSaved;

  const _AddEditDebtSheet({
    this.existingDebt,
    this.initialType = 0,
    required this.recentContacts,
    required this.onSaved,
  });

  @override
  State<_AddEditDebtSheet> createState() => _AddEditDebtSheetState();
}

class _AddEditDebtSheetState extends State<_AddEditDebtSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _personController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  late int _typeIndex; // 0 = Lent (I gave), 1 = Borrowed (I took)
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
  }

  @override
  void dispose() {
    _amountController.dispose();
    _personController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isDueDate) async {
    final initial = isDueDate ? _dueDate : _loanDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Theme.of(context).brightness,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isDueDate) {
          _dueDate = picked;
        } else {
          _loanDate = picked;
        }
      });
    }
  }

  void _setQuickDueDate(int days) {
    HapticFeedback.selectionClick();
    setState(() {
      _dueDate = DateTime.now().add(Duration(days: days));
    });
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
      AppSnackbar.showError(context, 'Please enter friend or lender name');
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

  @override
  Widget build(BuildContext context) {
    final isLend = _typeIndex == 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
          // ── Signature Curved Gradient Header Banner ──
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
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              children: [
                // Frosted Drag Handle
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

                // Title, Subtitle & Frosted Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Due Record' : 'Record Loan or Due',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEditing
                                ? 'Update transaction amounts, contacts & due dates'
                                : 'Track money given or taken with friends',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.76),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(7),
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
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Integrated Frosted Slider (I Lent vs I Borrowed) matching Top Bar
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  padding: const EdgeInsets.all(3.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _typeIndex = 0);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              gradient: isLend
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF10B981),
                                        Color(0xFF059669),
                                      ],
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(13),
                              boxShadow: isLend
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.north_east_rounded,
                                    size: 15,
                                    color: isLend
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.65),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'I Lent (To Receive)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isLend
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isLend
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _typeIndex = 1);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              gradient: !isLend
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFEF4444),
                                        Color(0xFFDC2626),
                                      ],
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(13),
                              boxShadow: !isLend
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFEF4444)
                                            .withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.south_west_rounded,
                                    size: 15,
                                    color: !isLend
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.65),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'I Borrowed (To Pay)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: !isLend
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: !isLend
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount Field
                    Text(
                      'Amount',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
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
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isLend
                                  ? AppColors.primary
                                  : const Color(0xFFE65100),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  color: AppColors.textLightOf(context),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                                border: InputBorder.none,
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Person Name Field
                    Text(
                      isLend ? 'Who did you lend to?' : 'Who did you borrow from?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 20,
                            color: AppColors.textSecondaryOf(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _personController,
                              textCapitalization: TextCapitalization.words,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Friend or Contact Name',
                                hintStyle: TextStyle(
                                  color: AppColors.textLightOf(context),
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Name is required';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Recent contacts chips
                    if (widget.recentContacts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 32,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.recentContacts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 6),
                          itemBuilder: (context, idx) {
                            final name = widget.recentContacts[idx];
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _personController.text = name;
                                });
                              },
                              child: Chip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                backgroundColor:
                                    AppColors.surfaceOf(context),
                                label: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Expected Repayment Date
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Expected Repayment Date',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _pickDate(true),
                          child: Text(
                            'Pick Date',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _pickDate(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.event_available_rounded,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  DateFormat('EEEE, dd MMMM yyyy')
                                      .format(_dueDate),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Due Date Shortcuts
                    Row(
                      children: [
                        _buildQuickDateChip('+3 Days', 3),
                        const SizedBox(width: 6),
                        _buildQuickDateChip('+1 Week', 7),
                        const SizedBox(width: 6),
                        _buildQuickDateChip('+2 Weeks', 14),
                        const SizedBox(width: 6),
                        _buildQuickDateChip('+1 Month', 30),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Urgency Selector
                    Text(
                      'Repayment Urgency',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Set expectations for repayment timeline & reminder priority',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textLightOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildUrgencyOption(
                          value: 'low',
                          label: 'Lenient',
                          subtitle: 'No rush / flexible',
                          color: const Color(0xFF2E7D32),
                          icon: Icons.spa_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildUrgencyOption(
                          value: 'medium',
                          label: 'Normal',
                          subtitle: 'Due on date',
                          color: const Color(0xFFF57C00),
                          icon: Icons.schedule_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildUrgencyOption(
                          value: 'high',
                          label: 'Strict',
                          subtitle: 'Urgent priority',
                          color: const Color(0xFFE53935),
                          icon: Icons.priority_high_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Date Lent / Borrowed
                    Text(
                      isLend ? 'Date Lent' : 'Date Borrowed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _pickDate(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 18,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  DateFormat('dd MMMM yyyy').format(_loanDate),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Note Field
                    Text(
                      'Note / Reason (optional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      child: TextFormField(
                        controller: _noteController,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimaryOf(context),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Dinner bill, Emergency cash',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: AppColors.textLightOf(context),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Remind on due date toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      child: SwitchListTile(
                        value: _remindOnDueDate,
                        onChanged: (val) =>
                            setState(() => _remindOnDueDate = val),
                        activeTrackColor: AppColors.primary,
                        title: Text(
                          'Remind me on repayment day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        subtitle: Text(
                          'Receive a notification reminder on ${DateFormat('dd MMM').format(_dueDate)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Auto-transaction info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLend
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : const Color(0xFFE65100).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isLend
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : const Color(0xFFE65100).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.sync_rounded,
                            size: 18,
                            color: isLend
                                ? AppColors.primary
                                : const Color(0xFFE65100),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isLend
                                  ? '✨ Lending automatically logs an Expense of ₹${_amountController.text.trim().isEmpty ? "0" : _amountController.text.trim()} under "Lending".'
                                  : '✨ Borrowing automatically logs an Income of ₹${_amountController.text.trim().isEmpty ? "0" : _amountController.text.trim()} under "Borrowing".',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isLend
                                    ? AppColors.primary
                                    : const Color(0xFFE65100),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLend
                              ? AppColors.primary
                              : const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSaving
                            ? const BuddyLoadingIndicator(size: 24)
                            : Text(
                                isEditing ? 'Update Record' : 'Save Record',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
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
    );
  }

  Widget _buildQuickDateChip(String label, int days) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _setQuickDueDate(days),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderOf(context),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
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
    required String subtitle,
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.12)
                : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.borderOf(context),
              width: isSelected ? 1.8 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected
                        ? color
                        : AppColors.textSecondaryOf(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? color
                          : AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? color : AppColors.textLightOf(context),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
