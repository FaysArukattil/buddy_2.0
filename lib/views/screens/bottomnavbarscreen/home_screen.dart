import 'package:buddy/services/notification_service.dart';
import 'package:buddy/services/notification_helper.dart';
import 'package:buddy/services/app_init_helper.dart';
import 'package:buddy/services/preference_service.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/utils/icon_helper.dart';
import 'package:buddy/views/screens/transaction_detail_screen.dart';
import 'package:buddy/views/screens/filtered_transactions_screen.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/views/widgets/setting_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:buddy/views/screens/add_transaction_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/bottom_navbar_screen.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';
import 'package:buddy/views/widgets/buddy_refresh_control.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  String _displayName = '';
  double _totalBalance = 0;
  double _income = 0;
  double _expenses = 0;
  int _balanceViewMode = 0; // 0 = Net Balance, 1 = Income only, 2 = Expense only
  late final PageController _balancePageController;
  Timer? _autoCycleTimer;
  int _autoCycleDirection = 1; // 1 = forward (0 -> 1 -> 2), -1 = backward (2 -> 1 -> 0)
  bool _userInteractedWithMode = false;
  bool _includeDebtsInBalance = true;
  final ScrollController _scrollController = ScrollController();
  double _segDragAccumX = 0;
  double _segDragStartPage = 0;
  int _lastSegHapticIndex = 0;
  double _headerDragAccumX = 0;
  double _headerDragStartPage = 0;
  int _lastHeaderHapticIndex = 0;
  List<TransactionModel> _transactions = [];
  List<TransactionModel> _cachedDisplayAll = [];
  List<TransactionModel> _cachedDisplayIncome = [];
  List<TransactionModel> _cachedDisplayExpense = [];
  Map<String, List<TransactionModel>> _cachedGroupedAll = {};
  Map<String, List<TransactionModel>> _cachedGroupedIncome = {};
  Map<String, List<TransactionModel>> _cachedGroupedExpense = {};
  bool _isLoading = true;
  StreamSubscription? _txnSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 HOME SCREEN INITIALIZED');

    WidgetsBinding.instance.addObserver(this);

    _balanceViewMode = PreferenceService.homeBalanceMode;
    if (_balanceViewMode != 0) {
      _userInteractedWithMode = true;
    }
    _balancePageController = PageController(initialPage: _balanceViewMode);
    _includeDebtsInBalance = PreferenceService.includeDebtsInHome;
    PreferenceService.includeDebtsInHomeNotifier.addListener(_onDebtPreferenceChanged);
    PreferenceService.homeBalanceModeNotifier.addListener(_onHomeModeChanged);

    _loadUser();

    // Listen to Firestore transactions in real-time and check auto-tracking prompt
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
      _checkAndPromptAutoTracking();
      _startAutoCycleTimer();
    });
  }

  void _startAutoCycleTimer() {
    _autoCycleTimer?.cancel();
    if (_userInteractedWithMode) return;
    _autoCycleTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted || _userInteractedWithMode) {
        timer.cancel();
        return;
      }
      if (_balancePageController.hasClients &&
          _balancePageController.positions.length == 1 &&
          _balancePageController.position.haveDimensions) {
        int nextMode = _balanceViewMode + _autoCycleDirection;
        if (nextMode > 2) {
          _autoCycleDirection = -1;
          nextMode = 1;
        } else if (nextMode < 0) {
          _autoCycleDirection = 1;
          nextMode = 1;
        }
        _onToggleMode(nextMode, isUserAction: false);
      }
    });
  }

  void _stopAutoCycle() {
    if (!_userInteractedWithMode) {
      _userInteractedWithMode = true;
      _autoCycleTimer?.cancel();
      _autoCycleTimer = null;
    }
  }

  void _onDebtPreferenceChanged() {
    if (!mounted) return;
    final newVal = PreferenceService.includeDebtsInHome;
    if (_includeDebtsInBalance != newVal) {
      setState(() {
        _includeDebtsInBalance = newVal;
      });
      if (_transactions.isNotEmpty) {
        _recalculateTotals(_transactions);
      }
    }
  }

  void _onHomeModeChanged() {
    if (!mounted) return;
    final newMode = PreferenceService.homeBalanceMode;
    if (_balanceViewMode != newMode) {
      _onToggleMode(newMode, isUserAction: false);
    }
  }

  @override
  void dispose() {
    _autoCycleTimer?.cancel();
    PreferenceService.includeDebtsInHomeNotifier.removeListener(_onDebtPreferenceChanged);
    PreferenceService.homeBalanceModeNotifier.removeListener(_onHomeModeChanged);
    _txnSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _balancePageController.dispose();
    super.dispose();
  }

  void _onToggleMode(int mode, {bool isUserAction = true}) {
    if (isUserAction) {
      _stopAutoCycle();
      PreferenceService.setHomeBalanceMode(mode);
    }
    final double currentPage = (_balancePageController.hasClients &&
            _balancePageController.positions.length == 1 &&
            _balancePageController.position.haveDimensions)
        ? (_balancePageController.page ?? _balanceViewMode.toDouble())
        : _balanceViewMode.toDouble();

    final bool pageAlreadyThere = (currentPage - mode).abs() < 0.01;
    if (_balanceViewMode == mode && pageAlreadyThere) return;
    if (isUserAction) {
      HapticFeedback.selectionClick();
    }
    if (_balanceViewMode != mode) {
      setState(() => _balanceViewMode = mode);
    }
    if (_balancePageController.hasClients &&
        _balancePageController.positions.length == 1 &&
        _balancePageController.position.haveDimensions) {
      _balancePageController.animateToPage(
        mode,
        duration: Duration(milliseconds: isUserAction ? 260 : 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _loadUser();
      AppInitHelper.syncNow();
      _checkAccessGrantedAfterReturn();
      if (!_userInteractedWithMode) {
        _startAutoCycleTimer();
      }
    } else if (state == AppLifecycleState.paused) {
      _autoCycleTimer?.cancel();
    }
  }

  void _startListening() {
    try {
      _txnSubscription?.cancel();
      _txnSubscription =
          FirestoreService.instance.getTransactionsStream().listen(
        (transactions) {
          if (!mounted) return;

          _transactions = transactions;
          _recalculateTotals(transactions);
          setState(() {
            _isLoading = false;
          });
        },
        onError: (e) {
          debugPrint('❌ HOME: Error listening to transactions: $e');
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } catch (e) {
      debugPrint('❌ HOME: Error starting listener: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _recalculateTotals(List<TransactionModel> transactions) {
    final now = DateTime.now();
    double monthIncome = 0;
    double monthExpense = 0;

    // Deduplicate once
    final deduped = TransactionModel.deduplicate(transactions);

    // Debt preference filter
    final base = _includeDebtsInBalance
        ? deduped
        : deduped
            .where((txn) => txn.category != 'Lending' && txn.category != 'Borrowing')
            .toList(growable: false);

    // Month totals for Hero header
    for (final txn in base) {
      if (txn.date.year == now.year && txn.date.month == now.month) {
        if (txn.type == 'income') {
          monthIncome += txn.amount;
        } else {
          monthExpense += txn.amount;
        }
      }
    }

    // Pre-filter by type for instant tab switching
    final incomeTxns = base
        .where((txn) => txn.type.toLowerCase().trim() == 'income')
        .toList(growable: false);
    final expenseTxns = base
        .where((txn) => txn.type.toLowerCase().trim() == 'expense')
        .toList(growable: false);

    // Cap display count on HomeScreen at 30 items for smooth 120fps performance
    const int homeMaxCount = 30;
    final cappedAll = base.length > homeMaxCount ? base.sublist(0, homeMaxCount) : base;
    final cappedIncome = incomeTxns.length > homeMaxCount ? incomeTxns.sublist(0, homeMaxCount) : incomeTxns;
    final cappedExpense = expenseTxns.length > homeMaxCount ? expenseTxns.sublist(0, homeMaxCount) : expenseTxns;

    Map<String, List<TransactionModel>> groupTxns(List<TransactionModel> list) {
      final map = <String, List<TransactionModel>>{};
      for (final txn in list) {
        final header = _getDateHeader(txn.date);
        map.putIfAbsent(header, () => []).add(txn);
      }
      return map;
    }

    final groupedAll = groupTxns(cappedAll);
    final groupedIncome = groupTxns(cappedIncome);
    final groupedExpense = groupTxns(cappedExpense);

    setState(() {
      _income = monthIncome;
      _expenses = monthExpense;
      _totalBalance = monthIncome - monthExpense;
      _cachedDisplayAll = cappedAll;
      _cachedDisplayIncome = cappedIncome;
      _cachedDisplayExpense = cappedExpense;
      _cachedGroupedAll = groupedAll;
      _cachedGroupedIncome = groupedIncome;
      _cachedGroupedExpense = groupedExpense;
    });
  }

  Future<void> refreshData() async {
    await _loadUser();
    if (_transactions.isNotEmpty) {
      _recalculateTotals(_transactions);
    }
    _startListening();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    final savedName = prefs.getString('name')?.trim() ?? '';
    final email = user?.email ?? prefs.getString('email')?.trim() ?? '';
    final savedIncludeDebts = PreferenceService.includeDebtsInHome;

    String displayName = savedName;
    if (displayName.isEmpty && user?.displayName != null) {
      displayName = user!.displayName!;
    }
    if (displayName.isEmpty && email.isNotEmpty) {
      displayName = email.contains('@') ? email.split('@').first : email;
      if (displayName.isNotEmpty) {
        displayName = displayName[0].toUpperCase() + displayName.substring(1);
      }
    }
    if (displayName.isEmpty) displayName = 'Guest';

    if (mounted) {
      setState(() {
        _displayName = displayName;
        _includeDebtsInBalance = savedIncludeDebts;
      });
      if (_transactions.isNotEmpty) {
        _recalculateTotals(_transactions);
      }
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _formatTime(DateTime d) {
    final hour = d.hour;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $ampm';
  }

  String _getDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txnDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(txnDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _checkAndPromptAutoTracking() async {
    if (!NotificationService.isSupportedPlatform) return;

    try {
      final isGranted = await NotificationService.isNotificationAccessGranted();
      if (isGranted) return; // Already enabled

      final prefs = await SharedPreferences.getInstance();
      final hasPrompted = prefs.getBool('prompted_auto_tracking_popup') ?? false;
      if (hasPrompted) return; // User already chose earlier

      if (!mounted) return;

      // Gentle delay so home screen finishes loading and animating in
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;

      _showAutoTrackingPromptSheet();
    } catch (e) {
      debugPrint('⚠️ Error checking auto tracking status: $e');
    }
  }

  Future<void> _checkAccessGrantedAfterReturn() async {
    // Only verify and notify if user just explicitly tapped 'Turn On'
    if (!NotificationService.awaitingPermissionReturn) return;
    NotificationService.awaitingPermissionReturn = false;

    try {
      final isGranted = await NotificationService.isNotificationAccessGranted();
      if (isGranted && mounted) {
        await NotificationService.setAutoDetectionEnabled(true);
        if (!mounted) return;
        AppSnackbar.showSuccess(
          context,
          'Auto-tracking is active! Bank & UPI SMS will log automatically.',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Error checking access after return: $e');
    }
  }

  void _showAutoTrackingPromptSheet() {
    final isDark = AppColors.isDark(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        final isShortScreen = screenHeight < 720;

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.90,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                  blurRadius: 30,
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
                  SizedBox(height: isShortScreen ? 14 : 20),

                  // Glowing Icon Badge
                  Container(
                    width: isShortScreen ? 56 : 68,
                    height: isShortScreen ? 56 : 68,
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
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: isShortScreen ? 28 : 34,
                    ),
                  ),
                  SizedBox(height: isShortScreen ? 12 : 18),

                  // Title
                  Text(
                    'Turn On Auto-Tracking?',
                    style: TextStyle(
                      fontSize: isShortScreen ? 19 : 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                      letterSpacing: -0.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Description
                  Text(
                    'Buddy can automatically track your expenses by securely reading bank & UPI notifications so you never have to log them manually.',
                    style: TextStyle(
                      fontSize: isShortScreen ? 12.5 : 13.5,
                      height: 1.4,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isShortScreen ? 14 : 20),

                  // Benefits Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.borderOf(context).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildPromptFeatureRow(
                          context,
                          icon: Icons.flash_on_rounded,
                          iconColor: const Color(0xFFFFB300),
                          title: 'Instant & Hands-Free',
                          desc: 'Auto-logs expenses from GPay, PhonePe, Paytm & SMS',
                        ),
                        const SizedBox(height: 10),
                        _buildPromptFeatureRow(
                          context,
                          icon: Icons.security_rounded,
                          iconColor: const Color(0xFF4CAF50),
                          title: '100% Private & On-Device',
                          desc: 'Notifications are read locally. No SMS data ever leaves your device',
                        ),
                        const SizedBox(height: 10),
                        _buildPromptFeatureRow(
                          context,
                          icon: Icons.tune_rounded,
                          iconColor: const Color(0xFF2196F3),
                          title: 'Full Control Anytime',
                          desc: 'Pause or turn it off whenever you want in Settings',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isShortScreen ? 16 : 22),

                  // Turn On Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(ctx);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('prompted_auto_tracking_popup', true);
                        await NotificationService.setAutoDetectionEnabled(true);
                        await NotificationHelper.requestNotificationPermission();
                        NotificationService.awaitingPermissionReturn = true;
                        await NotificationService.requestNotificationAccess();

                        if (!mounted) return;
                        AppSnackbar.showInfo(
                          context,
                          'Enable "Buddy" in Notification Access settings to start auto-tracking!',
                          duration: const Duration(seconds: 4),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded, size: 22),
                          SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Turn On Auto-Tracking',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Maybe Later Button
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: TextButton(
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('prompted_auto_tracking_popup', true);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondaryOf(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Maybe Later',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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
  }

  Widget _buildPromptFeatureRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
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
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SettingsModal(
        onDataCleared: () => refreshData(),
      ),
    );
  }

  Future<void> _showAddTransactionSheet() async {
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
              color: AppColors.backgroundOf(context),
              child: const AddTransactionScreen(),
            ),
          ),
        );
      },
    );

    if (result == true) {
      refreshData();
    }
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Instant O(1) lookup of pre-cached filtered & grouped transactions
    final displayTransactions = _balanceViewMode == 1
        ? _cachedDisplayIncome
        : (_balanceViewMode == 2 ? _cachedDisplayExpense : _cachedDisplayAll);

    final grouped = _balanceViewMode == 1
        ? _cachedGroupedIncome
        : (_balanceViewMode == 2 ? _cachedGroupedExpense : _cachedGroupedAll);

    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final topPadding = mq.padding.top;
    final double s = (screenW / 390.0).clamp(0.85, 1.25);
    final double headerBtnSize = (44 * s).clamp(40.0, 48.0);
    final topHeaderColor = AppColors.isDark(context)
        ? const Color(0xFF0F2624)
        : const Color(0xFF0F3632);

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: Stack(
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
          NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              if (notification.dragDetails != null) {
                _stopAutoCycle();
              }
              return false;
            },
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
            slivers: [
              // ── Dynamic Pull-To-Refresh with Coin & Matching Accent ──
              BuddyRefreshControl(
                onRefresh: refreshData,
                backgroundColor: topHeaderColor,
                topPadding: topPadding,
              ),

              // ── Seamless Unified Hero Header & Swipe Indicator (Swipable Top Portion) ──
              SliverToBoxAdapter(
                child: RepaintBoundary(
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    _stopAutoCycle();
                    _headerDragAccumX = 0;
                    _headerDragStartPage = (_balancePageController.hasClients &&
                            _balancePageController.positions.length == 1 &&
                            _balancePageController.position.haveDimensions)
                        ? (_balancePageController.page ?? _balanceViewMode.toDouble())
                        : _balanceViewMode.toDouble();
                    _lastHeaderHapticIndex = _headerDragStartPage.round();
                  },
                  onHorizontalDragUpdate: (details) {
                    _headerDragAccumX += details.delta.dx;
                    final double w = (_balancePageController.hasClients &&
                            _balancePageController.positions.length == 1 &&
                            _balancePageController.position.haveDimensions)
                        ? _balancePageController.position.viewportDimension
                        : MediaQuery.of(context).size.width;
                    final double deltaPages =
                        _headerDragAccumX / (w > 0 ? w : 300.0);
                    final double newPage =
                        (_headerDragStartPage + deltaPages).clamp(0.0, 2.0);
                    if (_balancePageController.hasClients &&
                        _balancePageController.positions.length == 1 &&
                        _balancePageController.position.haveDimensions) {
                      _balancePageController.position.jumpTo(newPage * w);
                    }
                    final int nearest = newPage.round().clamp(0, 2);
                    if (nearest != _lastHeaderHapticIndex) {
                      _lastHeaderHapticIndex = nearest;
                      HapticFeedback.selectionClick();
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    final double velocity = details.primaryVelocity ?? 0;
                    final double currentP = (_balancePageController.hasClients &&
                            _balancePageController.positions.length == 1 &&
                            _balancePageController.position.haveDimensions)
                        ? (_balancePageController.page ?? _balanceViewMode.toDouble())
                        : _balanceViewMode.toDouble();
                    int target = currentP.round();
                    if (velocity > 250) {
                      target = (currentP.floor() + 1).clamp(0, 2);
                    } else if (velocity < -250) {
                      target = (currentP.ceil() - 1).clamp(0, 2);
                    }
                    _onToggleMode(target.clamp(0, 2));
                  },
                  onHorizontalDragCancel: () {
                    final double currentP = (_balancePageController.hasClients &&
                            _balancePageController.positions.length == 1 &&
                            _balancePageController.position.haveDimensions)
                        ? (_balancePageController.page ?? _balanceViewMode.toDouble())
                        : _balanceViewMode.toDouble();
                    _onToggleMode(currentP.round().clamp(0, 2));
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.isDark(context)
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
                    (18 * s).clamp(14.0, 22.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ─── Top row: Avatar (Left) | Symmetric Settings Button (Right) ───
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left: Avatar + Clean Greeting & Name
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => context
                                    .findAncestorStateOfType<BottomNavbarScreenState>()
                                    ?.switchTab(3),
                                child: _buildProfileAvatar(headerBtnSize, s),
                              ),
                              SizedBox(width: (12 * s).clamp(8.0, 14.0)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _greeting(),
                                    style: TextStyle(
                                      fontSize: (12.5 * s).clamp(11.0, 14.0),
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.78),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _displayName,
                                    style: TextStyle(
                                      fontSize: (18 * s).clamp(15.0, 22.0),
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // Right: Symmetric Round Settings Button (Actual Settings Icon)
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _showSettings();
                            },
                            child: Container(
                              width: headerBtnSize,
                              height: headerBtnSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.settings_rounded,
                                  size: (22 * s).clamp(20.0, 24.0),
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: (18 * s).clamp(14.0, 24.0)),

                      // ─── Center Hero: Balance Label (Dynamic with real-time scrub & cross-fade) ───
                      SizedBox(
                        height: (20 * s).clamp(18.0, 24.0),
                        child: AnimatedBuilder(
                          animation: _balancePageController,
                          builder: (context, _) {
                            final double currentPage = (_balancePageController.hasClients &&
                                    _balancePageController.positions.length == 1 &&
                                    _balancePageController.position.haveDimensions)
                                ? (_balancePageController.page ?? _balanceViewMode.toDouble())
                                : _balanceViewMode.toDouble();

                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                _buildHeroLabel(0, 'Balance', currentPage, s),
                                _buildHeroLabel(1, 'Monthly Income', currentPage, s),
                                _buildHeroLabel(2, 'Monthly Expenses', currentPage, s),
                              ],
                            );
                          },
                        ),
                      ),

                      SizedBox(height: (6 * s).clamp(4.0, 8.0)),

                      // ─── Swipable Large Amount (Controlled seamlessly via top-level drag) ───
                      SizedBox(
                        height: (52 * s).clamp(44.0, 62.0),
                        child: PageView(
                          controller: _balancePageController,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (i) {
                            if (_balanceViewMode != i) {
                              setState(() => _balanceViewMode = i);
                            }
                          },
                          children: [
                            // Net Balance Page
                            Center(
                              child: Text(
                                FormatUtils.formatCurrency(_totalBalance, compact: false),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _totalBalance >= 0
                                      ? Colors.white
                                      : Colors.red.shade300,
                                  fontSize: (38 * s).clamp(30.0, 46.0),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Income Page
                            Center(
                              child: Text(
                                '+${FormatUtils.formatCurrency(_income, compact: false)}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFF69F0AE),
                                  fontSize: (38 * s).clamp(30.0, 46.0),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Expense Page
                            Center(
                              child: Text(
                                '-${FormatUtils.formatCurrency(_expenses, compact: false)}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFFFF8A80),
                                  fontSize: (38 * s).clamp(30.0, 46.0),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.0,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: (8 * s).clamp(6.0, 12.0)),

                      // ─── Centered Trend Capsule (Matching Reference Mockup & Cross-fading) ───
                      AnimatedBuilder(
                        animation: _balancePageController,
                        builder: (context, _) {
                          final double currentPage = (_balancePageController.hasClients &&
                                  _balancePageController.positions.length == 1 &&
                                  _balancePageController.position.haveDimensions)
                              ? (_balancePageController.page ?? _balanceViewMode.toDouble())
                              : _balanceViewMode.toDouble();

                          return Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: (14 * s).clamp(11.0, 18.0),
                              vertical: (6 * s).clamp(4.5, 7.5),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                                width: 1.0,
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                _buildMiniBadge(
                                  0,
                                  Icons.north_east_rounded,
                                  _totalBalance >= 0
                                      ? 'Net Available'
                                      : 'Deficit this month',
                                  Colors.white,
                                  currentPage,
                                  s,
                                ),
                                _buildMiniBadge(
                                  1,
                                  Icons.arrow_upward_rounded,
                                  'Total Received this month',
                                  const Color(0xFF69F0AE),
                                  currentPage,
                                  s,
                                ),
                                _buildMiniBadge(
                                  2,
                                  Icons.arrow_downward_rounded,
                                  'Total Spent this month',
                                  const Color(0xFFFF8A80),
                                  currentPage,
                                  s,
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      if (!_includeDebtsInBalance) ...[
                        SizedBox(height: (10 * s).clamp(6.0, 14.0)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.20),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'Debts Excluded',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],

                      SizedBox(height: (14 * s).clamp(10.0, 18.0)),

                      // ─── Seamless Switcher: Attached cleanly at bottom of hero header ───
                      _buildSegmentedToggleBar(s),
                    ],
                  ),
                ),
              ),

              // ── Glassy Swipe Indicator: Positioned cleanly outside the top hero container ──
              Padding(
                padding: EdgeInsets.only(
                  top: (12 * s).clamp(10.0, 16.0),
                  bottom: (2 * s).clamp(0.0, 4.0),
                ),
                child: _buildSwipeIndicator(s),
              ),
            ],
          ),
        ),
      ),
    ),
              // ── Recent Transactions Header (Immediately below hero card) ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    (20 * s).clamp(16.0, 26.0),
                    (20 * s).clamp(16.0, 26.0),
                    (20 * s).clamp(16.0, 26.0),
                    (10 * s).clamp(6.0, 14.0),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: anim,
                              curve: Curves.easeOutCubic,
                            )),
                            child: child,
                          ),
                        ),
                        child: Text(
                          _balanceViewMode == 1
                              ? 'Recent Income'
                              : (_balanceViewMode == 2
                                  ? 'Recent Expenses'
                                  : 'Recent Transactions'),
                          key: ValueKey<int>(_balanceViewMode),
                          style: TextStyle(
                            fontSize: (17 * s).clamp(15.0, 19.0),
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimaryOf(context),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          final seeAllType = _balanceViewMode == 1
                              ? 'Income'
                              : (_balanceViewMode == 2 ? 'Expense' : 'All');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FilteredTransactionsScreen(type: seeAllType),
                            ),
                          ).then((_) => refreshData());
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: (11 * s).clamp(9.0, 15.0),
                            vertical: (5 * s).clamp(4.0, 7.0),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.isDark(context)
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFF0F3632).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.isDark(context)
                                  ? Colors.white.withValues(alpha: 0.20)
                                  : const Color(0xFF0F3632).withValues(alpha: 0.18),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: (14 * s).clamp(12.0, 16.0),
                                color: AppColors.isDark(context)
                                    ? Colors.white
                                    : const Color(0xFF0F3632),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'History',
                                style: TextStyle(
                                  color: AppColors.isDark(context)
                                      ? Colors.white
                                      : const Color(0xFF0F3632),
                                  fontSize: (11.5 * s).clamp(10.5, 13.0),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
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

              // Transaction List (Smoothly animated into place via AnimatedSwitcher + AnimatedSize)
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: BuddyLoadingIndicator(size: 56),
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.topCenter,
                          children: <Widget>[
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: KeyedSubtree(
                        key: ValueKey<int>(_balanceViewMode),
                        child: _buildTransactionListSection(
                          displayTransactions,
                          grouped,
                          context,
                          s,
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
    );
  }

  Widget _buildProfileAvatar(double size, double s) {
    final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
    final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        image: hasPhoto
            ? DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasPhoto
          ? null
          : Center(
              child: Text(
                _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'B',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: (17 * s).clamp(15.0, 20.0),
                ),
              ),
            ),
    );
  }

  Widget _buildSegmentedToggleBar(double s) {
    const double barHeight = 40.0;
    return Container(
      height: barHeight,
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

          return AnimatedBuilder(
            animation: _balancePageController,
            builder: (context, _) {
              final double currentPage = _balancePageController.hasClients &&
                      _balancePageController.positions.length == 1 &&
                      _balancePageController.position.haveDimensions
                  ? (_balancePageController.page ?? _balanceViewMode.toDouble())
                  : _balanceViewMode.toDouble();

              final double leftOffset = (currentPage * segWidth + pillInset)
                  .clamp(pillInset, totalWidth - segWidth + pillInset);

              Color c1, c2, borderC, glowC;
              if (currentPage <= 1.0) {
                final double t = currentPage.clamp(0.0, 1.0);
                c1 = Color.lerp(
                  Colors.white.withValues(alpha: 0.28),
                  AppColors.income.withValues(alpha: 0.38),
                  t,
                )!;
                c2 = Color.lerp(
                  Colors.white.withValues(alpha: 0.15),
                  AppColors.income.withValues(alpha: 0.22),
                  t,
                )!;
                borderC = Color.lerp(
                  Colors.white.withValues(alpha: 0.45),
                  AppColors.income.withValues(alpha: 0.60),
                  t,
                )!;
                glowC = Color.lerp(
                  Colors.white.withValues(alpha: 0.15),
                  AppColors.income.withValues(alpha: 0.25),
                  t,
                )!;
              } else {
                final double t = (currentPage - 1.0).clamp(0.0, 1.0);
                c1 = Color.lerp(
                  AppColors.income.withValues(alpha: 0.38),
                  AppColors.expense.withValues(alpha: 0.38),
                  t,
                )!;
                c2 = Color.lerp(
                  AppColors.income.withValues(alpha: 0.22),
                  AppColors.expense.withValues(alpha: 0.22),
                  t,
                )!;
                borderC = Color.lerp(
                  AppColors.income.withValues(alpha: 0.60),
                  AppColors.expense.withValues(alpha: 0.60),
                  t,
                )!;
                glowC = Color.lerp(
                  AppColors.income.withValues(alpha: 0.25),
                  AppColors.expense.withValues(alpha: 0.25),
                  t,
                )!;
              }

              final pillGradient = LinearGradient(
                colors: [c1, c2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              );
              final pillBorder = borderC;
              final glowColor = glowC;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) {
                  _stopAutoCycle();
                  _segDragAccumX = 0;
                  _segDragStartPage = currentPage;
                  _lastSegHapticIndex = currentPage.round();
                },
                onHorizontalDragUpdate: (details) {
                  _segDragAccumX += details.delta.dx;
                  final double deltaPages = _segDragAccumX / segWidth;
                  final double newPage =
                      (_segDragStartPage + deltaPages).clamp(0.0, 2.0);
                  if (_balancePageController.hasClients &&
                      _balancePageController.positions.length == 1 &&
                      _balancePageController.position.haveDimensions) {
                    final double w = _balancePageController
                        .position.viewportDimension;
                    _balancePageController.position.jumpTo(newPage * w);
                  }
                  final int nearest = newPage.round().clamp(0, 2);
                  if (nearest != _lastSegHapticIndex) {
                    _lastSegHapticIndex = nearest;
                    HapticFeedback.selectionClick();
                  }
                },
                onHorizontalDragEnd: (details) {
                  final double velocity = details.primaryVelocity ?? 0;
                  final double currentP = (_balancePageController.hasClients &&
                          _balancePageController.positions.length == 1 &&
                          _balancePageController.position.haveDimensions)
                      ? (_balancePageController.page ?? currentPage)
                      : currentPage;
                  int target = currentP.round();
                  if (velocity > 250) {
                    target = (currentP.floor() + 1).clamp(0, 2);
                  } else if (velocity < -250) {
                    target = (currentP.ceil() - 1).clamp(0, 2);
                  }
                  _onToggleMode(target.clamp(0, 2));
                },
                onHorizontalDragCancel: () {
                  final int target = (_balancePageController.hasClients &&
                          _balancePageController.positions.length == 1 &&
                          _balancePageController.position.haveDimensions)
                      ? (_balancePageController.page ?? currentPage).round().clamp(0, 2)
                      : currentPage.round().clamp(0, 2);
                  _onToggleMode(target);
                },
                child: SizedBox(
                  height: barHeight,
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
                              color: pillBorder,
                              width: 1.1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: glowColor,
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildToggleTab(0, 'Balance', currentPage, s),
                          ),
                          Expanded(
                            child: _buildToggleTab(1, 'Income', currentPage, s),
                          ),
                          Expanded(
                            child: _buildToggleTab(2, 'Expense', currentPage, s),
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

  Widget _buildTransactionListSection(
    List<TransactionModel> displayTransactions,
    Map<String, List<TransactionModel>> grouped,
    BuildContext context,
    double s,
  ) {
    if (displayTransactions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 48.0),
        child: Center(
          child: GestureDetector(
            onTap: _showAddTransactionSheet,
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _balanceViewMode == 1
                      ? Icons.trending_up_rounded
                      : (_balanceViewMode == 2
                          ? Icons.trending_down_rounded
                          : Icons.receipt_long_rounded),
                  size: 64,
                  color: AppColors.isDark(context)
                      ? AppColors.textMutedOf(context).withValues(alpha: 0.4)
                      : Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  _balanceViewMode == 1
                      ? 'No income transactions'
                      : (_balanceViewMode == 2
                          ? 'No expense transactions'
                          : 'No transactions yet'),
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _balanceViewMode == 1
                      ? 'Tap to add an income transaction'
                      : (_balanceViewMode == 2
                          ? 'Tap to add an expense transaction'
                          : 'Tap to add your first transaction'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];
    bool isFirst = true;
    for (final entry in grouped.entries) {
      children.add(
        Padding(
          padding: EdgeInsets.only(
            top: isFirst ? 0 : 20,
            bottom: 10,
          ),
          child: Row(
            children: [
              Text(
                entry.key.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondaryOf(context),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Divider(
                  color: AppColors.borderOf(context),
                  thickness: 1,
                ),
              ),
            ],
          ),
        ),
      );
      isFirst = false;

      for (final txn in entry.value) {
        children.add(_buildTransactionTile(txn));
      }
    }

    if (_transactions.length > 30) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Center(
            child: TextButton.icon(
              onPressed: () {
                final seeAllType = _balanceViewMode == 1
                    ? 'Income'
                    : (_balanceViewMode == 2 ? 'Expense' : 'All');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FilteredTransactionsScreen(type: seeAllType),
                  ),
                ).then((_) => refreshData());
              },
              icon: const Icon(Icons.history_rounded, size: 16),
              label: Text(
                _balanceViewMode == 1
                    ? 'View all income in History'
                    : (_balanceViewMode == 2
                        ? 'View all expenses in History'
                        : 'View all transactions in History'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildToggleTab(int index, String label, double currentPage, double s) {
    final double dist = (currentPage - index).abs();
    final double activeFactor = (1.0 - dist).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onToggleMode(index),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: Color.lerp(
              Colors.white.withValues(alpha: 0.60),
              Colors.white,
              activeFactor,
            ),
            fontSize: (12.5 * s).clamp(11.0, 14.0),
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroLabel(int index, String text, double currentPage, double s) {
    final double dist = (currentPage - index).abs();
    final double opacity = (1.0 - dist).clamp(0.0, 1.0);
    if (opacity <= 0.001) return const SizedBox.shrink();

    final double translateX = (index - currentPage) * 16.0;

    return Transform.translate(
      offset: Offset(translateX, 0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: (14 * s).clamp(13.0, 16.0),
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: (0.85 * opacity).clamp(0.0, 1.0)),
          letterSpacing: 0.3,
        ),
        maxLines: 1,
      ),
    );
  }

  Widget _buildMiniBadge(
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

    final double translateX = (index - currentPage) * 12.0;

    return Transform.translate(
      offset: Offset(translateX, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: (13 * s).clamp(11.0, 15.0),
            color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
              fontSize: (11.5 * s).clamp(10.5, 13.0),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeIndicator(double s) {
    final isDark = AppColors.isDark(context);
    return AnimatedBuilder(
      animation: _balancePageController,
      builder: (context, _) {
        final double currentPage = _balancePageController.hasClients &&
                _balancePageController.positions.length == 1 &&
                _balancePageController.position.haveDimensions
            ? (_balancePageController.page ?? _balanceViewMode.toDouble())
            : _balanceViewMode.toDouble();

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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onToggleMode(index),
      child: Container(
        width: dotWidth.clamp(5.0, 20.0),
        height: dotHeight,
        decoration: BoxDecoration(
          color: dotColor,
          borderRadius: BorderRadius.circular(dotHeight / 2),
          boxShadow: factor > 0.3
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.35 * factor),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
      ),
    );
  }



  Widget _buildTransactionTile(TransactionModel txn) {
    final isIncome = txn.type.toLowerCase().trim() == 'income';
    final catColor = AppColors.getCategoryColor(txn.category);
    final isAutoDetected = txn.autoDetected;
    final title = txn.displayTitle;
    final isDark = AppColors.isDark(context);

    final cardBg = isAutoDetected
        ? (isDark ? const Color(0xFF102825) : const Color(0xFFEEF6F5))
        : AppColors.cardOf(context);
    final cardBorder = isAutoDetected
        ? (isDark
            ? const Color(0xFF1E5D57).withValues(alpha: 0.55)
            : const Color(0xFF0F3632).withValues(alpha: 0.25))
        : AppColors.borderOf(context).withValues(alpha: 0.5);
    final cardShadow = isAutoDetected
        ? [
            BoxShadow(
              color: const Color(0xFF0F3632).withValues(alpha: isDark ? 0.25 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ]
        : AppColors.cardShadowOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cardBorder,
            width: isAutoDetected ? 1.2 : 1.0,
          ),
          boxShadow: cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    final displayMap = txn.toDisplayMap();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TransactionDetailScreen(data: displayMap),
                      ),
                    ).then((_) => refreshData());
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 18.5, // 4.5px category stripe + 14px padding
                      right: 14.0,
                      top: 12.0,
                      bottom: 12.0,
                    ),
                    child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    IconHelper.getIcon(txn.icon),
                                    color: catColor,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                          color: AppColors.textPrimaryOf(context),
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: catColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              txn.category,
                                              style: TextStyle(
                                                color: catColor,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _formatTime(txn.date),
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
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${isIncome ? '+' : '-'}${FormatUtils.formatCurrency(txn.amount, compact: false)}',
                                      style: TextStyle(
                                        color: isIncome ? AppColors.income : AppColors.expense,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15.5,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isIncome ? 'Income' : 'Expense',
                                      style: TextStyle(
                                        color: isIncome
                                            ? AppColors.income.withValues(alpha: 0.85)
                                            : AppColors.textLightOf(context),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Category-specific brand color vertical stripe on the left edge (zero-cost full height layout)
                      Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4.5,
                child: ColoredBox(color: catColor),
              ),
              if (isAutoDetected)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? const [Color(0xFF163E3B), Color(0xFF2C7A72)]
                            : const [Color(0xFF0F3632), Color(0xFF1E5D57)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomRight: Radius.circular(8),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F3632).withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 9.5,
                          color: Colors.white,
                        ),
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
      ),
    );
  }
}
