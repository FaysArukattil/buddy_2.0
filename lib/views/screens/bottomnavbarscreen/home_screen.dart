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
  bool _includeDebtsInBalance = true;
  bool _notifiedGranted = false;
  bool _hideBalance = false;
  final ScrollController _scrollController = ScrollController();
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  StreamSubscription? _txnSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 HOME SCREEN INITIALIZED');

    WidgetsBinding.instance.addObserver(this);

    _balancePageController = PageController(initialPage: _balanceViewMode);
    _includeDebtsInBalance = PreferenceService.includeDebtsInHome;
    PreferenceService.includeDebtsInHomeNotifier.addListener(_onDebtPreferenceChanged);

    _loadUser();

    // Listen to Firestore transactions in real-time and check auto-tracking prompt
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
      _checkAndPromptAutoTracking();
    });
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

  @override
  void dispose() {
    PreferenceService.includeDebtsInHomeNotifier.removeListener(_onDebtPreferenceChanged);
    _txnSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _balancePageController.dispose();
    super.dispose();
  }

  void _onToggleMode(int mode) {
    if (_balanceViewMode == mode) return;
    HapticFeedback.selectionClick();
    setState(() => _balanceViewMode = mode);
    if (_balancePageController.hasClients) {
      _balancePageController.animateToPage(
        mode,
        duration: const Duration(milliseconds: 280),
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

    for (final txn in transactions) {
      final isDebt = txn.category == 'Lending' || txn.category == 'Borrowing';
      if (!_includeDebtsInBalance && isDebt) {
        continue;
      }
      if (txn.date.year == now.year && txn.date.month == now.month) {
        if (txn.type == 'income') {
          monthIncome += txn.amount;
        } else {
          monthExpense += txn.amount;
        }
      }
    }

    setState(() {
      _income = monthIncome;
      _expenses = monthExpense;
      _totalBalance = monthIncome - monthExpense;
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
    if (_notifiedGranted) return;
    try {
      final isGranted = await NotificationService.isNotificationAccessGranted();
      if (isGranted && mounted) {
        _notifiedGranted = true;
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
        return Container(
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
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
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
              const SizedBox(height: 20),

              // Glowing Icon Badge
              Container(
                width: 68,
                height: 68,
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
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Text(
                'Turn On Auto-Tracking?',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                  letterSpacing: -0.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // Description
              Text(
                'Buddy can automatically track your expenses by securely reading bank & UPI notifications so you never have to log them manually.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textSecondaryOf(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Benefits Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    const SizedBox(height: 12),
                    _buildPromptFeatureRow(
                      context,
                      icon: Icons.security_rounded,
                      iconColor: const Color(0xFF4CAF50),
                      title: '100% Private & On-Device',
                      desc: 'Notifications are read locally. No SMS data ever leaves your device',
                    ),
                    const SizedBox(height: 12),
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
              const SizedBox(height: 24),

              // Turn On Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('prompted_auto_tracking_popup', true);
                    await NotificationService.setAutoDetectionEnabled(true);
                    await NotificationHelper.requestNotificationPermission();
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
                      Text(
                        'Turn On Auto-Tracking',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Maybe Later Button
              SizedBox(
                width: double.infinity,
                height: 44,
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

    // Filter display transactions based on debt separation setting and balance view mode
    final dedupedTransactions = TransactionModel.deduplicate(_transactions);
    final baseTransactions = _includeDebtsInBalance
        ? dedupedTransactions
        : dedupedTransactions
            .where((txn) => txn.category != 'Lending' && txn.category != 'Borrowing')
            .toList();

    final displayTransactions = _balanceViewMode == 1
        ? baseTransactions.where((txn) => txn.type.toLowerCase().trim() == 'income').toList()
        : _balanceViewMode == 2
            ? baseTransactions.where((txn) => txn.type.toLowerCase().trim() == 'expense').toList()
            : baseTransactions;

    // Group transactions by date
    final grouped = <String, List<TransactionModel>>{};
    for (final txn in displayTransactions) {
      final header = _getDateHeader(txn.date);
      grouped.putIfAbsent(header, () => []).add(txn);
    }

    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final topPadding = mq.padding.top;
    final double s = (screenW / 390.0).clamp(0.85, 1.25);
    final double headerBtnSize = (44 * s).clamp(40.0, 48.0);

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // ── Dynamic Pull-To-Refresh with Coin & Matching Accent ──
          BuddyRefreshControl(
            onRefresh: refreshData,
            backgroundColor: Colors.transparent,
          ),

          // ── Seamless Unified Hero Header (Signature Teal App Theme) ──
          SliverToBoxAdapter(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (DragEndDetails details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -150) {
                  // Swiped Left -> go to next mode (0 -> 1 -> 2)
                  if (_balanceViewMode < 2) {
                    _onToggleMode(_balanceViewMode + 1);
                  }
                } else if (velocity > 150) {
                  // Swiped Right -> go to previous mode (2 -> 1 -> 0)
                  if (_balanceViewMode > 0) {
                    _onToggleMode(_balanceViewMode - 1);
                  }
                }
              },
              child: Container(
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

                      // ─── Center Hero: Balance Label + Eye Toggle ───
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _balanceViewMode == 1
                                ? 'Monthly Income'
                                : (_balanceViewMode == 2
                                    ? 'Monthly Expenses'
                                    : 'Balance'),
                            style: TextStyle(
                              fontSize: (14 * s).clamp(13.0, 16.0),
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _hideBalance = !_hideBalance);
                            },
                            child: Icon(
                              _hideBalance
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: (18 * s).clamp(16.0, 20.0),
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: (6 * s).clamp(4.0, 8.0)),

                      // ─── Swipable Large Amount (PageView so swiping changes view mode) ───
                      SizedBox(
                        height: (52 * s).clamp(44.0, 62.0),
                        child: PageView(
                          controller: _balancePageController,
                          physics: const PageScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          onPageChanged: (i) {
                            setState(() => _balanceViewMode = i);
                          },
                          children: [
                            // Net Balance Page
                            Center(
                              child: Text(
                                _hideBalance
                                    ? '••••••••'
                                    : FormatUtils.formatCurrency(_totalBalance, compact: false),
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
                                _hideBalance
                                    ? '••••••••'
                                    : '+${FormatUtils.formatCurrency(_income, compact: false)}',
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
                                _hideBalance
                                    ? '••••••••'
                                    : '-${FormatUtils.formatCurrency(_expenses, compact: false)}',
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

                      // ─── Centered Trend Capsule (Matching Reference Mockup) ───
                      Container(
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _balanceViewMode == 1
                                  ? Icons.arrow_upward_rounded
                                  : (_balanceViewMode == 2
                                      ? Icons.arrow_downward_rounded
                                      : Icons.north_east_rounded),
                              size: (13 * s).clamp(11.0, 15.0),
                              color: _balanceViewMode == 1
                                  ? const Color(0xFF69F0AE)
                                  : (_balanceViewMode == 2
                                      ? const Color(0xFFFF8A80)
                                      : Colors.white),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _balanceViewMode == 1
                                  ? 'Total Received this month'
                                  : (_balanceViewMode == 2
                                      ? 'Total Spent this month'
                                      : (_totalBalance >= 0
                                          ? 'Net Available'
                                          : 'Deficit this month')),
                              style: TextStyle(
                                color: _balanceViewMode == 1
                                    ? const Color(0xFF69F0AE)
                                    : (_balanceViewMode == 2
                                        ? const Color(0xFFFF8A80)
                                        : Colors.white),
                                fontSize: (11.5 * s).clamp(10.5, 13.0),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: (16 * s).clamp(12.0, 22.0)),

                      // ─── Sub-bar: Debts tag & Integrated History button ───
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (!_includeDebtsInBalance)
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
                            )
                          else
                            const SizedBox.shrink(),

                          // Integrated History button
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const FilteredTransactionsScreen(type: 'All'),
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
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.history_rounded,
                                    size: (14 * s).clamp(12.0, 16.0),
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'History',
                                    style: TextStyle(
                                      color: Colors.white,
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

                      SizedBox(height: (10 * s).clamp(8.0, 14.0)),

                      // ─── Seamless Switcher: Attached cleanly at bottom of hero header ───
                      _buildSegmentedToggleBar(s),
                    ],
                  ),
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
                      Text(
                        _balanceViewMode == 1
                            ? 'Recent Income'
                            : (_balanceViewMode == 2
                                ? 'Recent Expenses'
                                : 'Recent Transactions'),
                        style: TextStyle(
                          fontSize: (17 * s).clamp(15.0, 19.0),
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimaryOf(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (displayTransactions.isNotEmpty)
                        TextButton(
                          onPressed: () {
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
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            textStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: (13 * s).clamp(11.5, 14.5),
                            ),
                          ),
                          child: const Text('See all'),
                        ),
                    ],
                  ),
                ),
              ),

            // Transaction List
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
            else if (displayTransactions.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: GestureDetector(
                      onTap: _showAddTransactionSheet,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
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
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // Build flat list with date headers
                      int itemIndex = 0;
                      for (final entry in grouped.entries) {
                        // Date header
                        if (index == itemIndex) {
                          return Padding(
                            padding: EdgeInsets.only(
                              top: itemIndex == 0 ? 0 : 20,
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
                          );
                        }
                        itemIndex++;

                        // Transactions under this header
                        for (final txn in entry.value) {
                            if (index == itemIndex) {
                              return _buildTransactionTile(txn);
                            }
                            itemIndex++;
                        }
                      }
                      return const SizedBox.shrink();
                    },
                    childCount: grouped.entries.fold<int>(
                      0,
                      (sum, e) => sum + 1 + e.value.length,
                    ),
                  ),
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
      child: AnimatedBuilder(
        animation: _balancePageController,
        builder: (context, _) {
          final double currentPage = _balancePageController.hasClients &&
                  _balancePageController.position.haveDimensions
              ? (_balancePageController.page ?? _balanceViewMode.toDouble())
              : _balanceViewMode.toDouble();

          return LayoutBuilder(
            builder: (context, constraints) {
              final double segWidth = constraints.maxWidth / 3;
              final double leftOffset =
                  (currentPage * segWidth).clamp(0.0, constraints.maxWidth - segWidth);

              Gradient pillGradient;
              Color pillBorder;
              Color glowColor;

              if (currentPage < 0.8) {
                pillGradient = LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.28),
                    Colors.white.withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                );
                pillBorder = Colors.white.withValues(alpha: 0.45);
                glowColor = Colors.white.withValues(alpha: 0.15);
              } else if (currentPage >= 0.8 && currentPage <= 1.5) {
                pillGradient = LinearGradient(
                  colors: [
                    AppColors.income.withValues(alpha: 0.38),
                    AppColors.income.withValues(alpha: 0.22),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                );
                pillBorder = AppColors.income.withValues(alpha: 0.60);
                glowColor = AppColors.income.withValues(alpha: 0.25);
              } else {
                pillGradient = LinearGradient(
                  colors: [
                    AppColors.expense.withValues(alpha: 0.38),
                    AppColors.expense.withValues(alpha: 0.22),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                );
                pillBorder = AppColors.expense.withValues(alpha: 0.60);
                glowColor = AppColors.expense.withValues(alpha: 0.25);
              }

              return Stack(
                children: [
                  Positioned(
                    left: leftOffset,
                    width: segWidth,
                    top: 0,
                    bottom: 0,
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
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildToggleTab(int index, String label, double currentPage, double s) {
    final bool isSelected = (_balancePageController.hasClients &&
            _balancePageController.position.haveDimensions
        ? (currentPage.round() == index)
        : (_balanceViewMode == index));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onToggleMode(index),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.65),
            fontSize: (12.5 * s).clamp(11.0, 14.0),
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: -0.2,
          ),
          child: Text(label),
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
        ? (isDark ? const Color(0xFF191830) : const Color(0xFFF7F6FE))
        : AppColors.cardOf(context);
    final cardBorder = isAutoDetected
        ? (isDark
            ? const Color(0xFF7C4DFF).withValues(alpha: 0.42)
            : const Color(0xFF673AB7).withValues(alpha: 0.28))
        : AppColors.borderOf(context).withValues(alpha: 0.5);
    final cardShadow = isAutoDetected
        ? [
            BoxShadow(
              color: const Color(0xFF7C4DFF).withValues(alpha: isDark ? 0.16 : 0.08),
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
              IntrinsicHeight(
                child: Row(
                  children: [
                    // Category-specific brand color vertical stripe on the left edge
                    Container(
                      width: 4.5,
                      color: catColor,
                    ),
                    Expanded(
                      child: Material(
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
                            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
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
                    ),
                  ],
                ),
              ),
              if (isAutoDetected)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomRight: Radius.circular(8),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x357C4DFF),
                          blurRadius: 4,
                          offset: Offset(0, 1),
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
