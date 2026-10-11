import 'package:buddy/services/notification_service.dart';
import 'package:buddy/services/notification_helper.dart';
import 'package:buddy/services/app_init_helper.dart';
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
  bool _includeDebtsInBalance = true;
  bool _notifiedGranted = false;
  late final AnimationController _controller;
  late final Animation<double> _bobAnimation;
  final ScrollController _scrollController = ScrollController();
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  StreamSubscription? _txnSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 HOME SCREEN INITIALIZED');

    WidgetsBinding.instance.addObserver(this);

    _loadUser();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _bobAnimation = Tween<double>(
      begin: -3.0,
      end: 3.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);

    // Listen to Firestore transactions in real-time and check auto-tracking prompt
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
      _checkAndPromptAutoTracking();
    });
  }

  @override
  void dispose() {
    _txnSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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
    final savedIncludeDebts = prefs.getBool('include_debts_in_balance') ?? true;

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

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Filter display transactions based on debt separation setting
    final displayTransactions = _includeDebtsInBalance
        ? _transactions
        : _transactions
            .where((txn) => txn.category != 'Lending' && txn.category != 'Borrowing')
            .toList();

    // Group transactions by date
    final grouped = <String, List<TransactionModel>>{};
    for (final txn in displayTransactions) {
      final header = _getDateHeader(txn.date);
      grouped.putIfAbsent(header, () => []).add(txn);
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refreshData,
          color: AppColors.primary,
          backgroundColor: AppColors.cardOf(context),
          displacement: 60,
          strokeWidth: 3.0,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _greeting(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _displayName,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimaryOf(context),
                                      letterSpacing: -0.5,
                                    ),
                                    textAlign: TextAlign.start,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _showSettings,
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardOf(context),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.borderOf(context),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.settings_rounded,
                                    size: 20,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => context.findAncestorStateOfType<BottomNavbarScreenState>()?.switchTab(3),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFFB74D), // Light gold
                                        Color(0xFFFF8A65), // Peach
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'G',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Balance Card (Credit Card look)
                      AnimatedBuilder(
                        animation: _bobAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _bobAnimation.value),
                            child: child,
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1E5D57), // Deep emerald
                                Color(0xFF3B8E85), // Soft teal
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1E5D57).withValues(alpha: 0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Row: Toggles + Card Chip & Debts badge
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Toggles: Balance | Income | Expense
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.15),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildCardTogglePill(0, 'Balance'),
                                        const SizedBox(width: 3),
                                        _buildCardTogglePill(1, 'Income'),
                                        const SizedBox(width: 3),
                                        _buildCardTogglePill(2, 'Expense'),
                                      ],
                                    ),
                                  ),

                                  Row(
                                    children: [
                                      if (!_includeDebtsInBalance) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.white24),
                                          ),
                                          child: const Text(
                                            'Debts Excl.',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      // Gold card chip
                                      Container(
                                        width: 38,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.2),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                children: List.generate(3, (_) => Container(width: 4, height: 4, color: Colors.black26)),
                                              ),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                children: List.generate(3, (_) => Container(width: 4, height: 4, color: Colors.black26)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _balanceViewMode == 0
                                    ? 'CURRENT BALANCE'
                                    : (_balanceViewMode == 1 ? 'TOTAL MONTHLY INCOME' : 'TOTAL MONTHLY EXPENSES'),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _balanceViewMode == 0
                                    ? FormatUtils.formatCurrency(
                                        _totalBalance,
                                        compact: false,
                                      )
                                    : (_balanceViewMode == 1
                                        ? '+${FormatUtils.formatCurrency(_income, compact: false)}'
                                        : '-${FormatUtils.formatCurrency(_expenses, compact: false)}'),
                                style: TextStyle(
                                  color: _balanceViewMode == 0
                                      ? (_totalBalance >= 0 ? Colors.white : Colors.red.shade300)
                                      : (_balanceViewMode == 1
                                          ? const Color(0xFF69F0AE)
                                          : const Color(0xFFFF8A80)),
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'CARD HOLDER',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _displayName.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'BUDDY PAY',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      Text(
                                        'PREMIUM',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              // Stats Capsules (Glassmorphic look)
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatTile(
                                      label: 'Income',
                                      value: _income,
                                      icon: Icons.arrow_upward_rounded,
                                      color: AppColors.income,
                                      mode: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatTile(
                                      label: 'Expenses',
                                      value: _expenses,
                                      icon: Icons.arrow_downward_rounded,
                                      color: AppColors.expense,
                                      mode: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Quick Actions Section
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildQuickActionButton(
                            icon: Icons.add_circle_outline_rounded,
                            label: 'Add Txn',
                            color: const Color(0xFF69AEA9),
                            onTap: _showAddTransactionSheet,
                          ),
                          _buildQuickActionButton(
                            icon: Icons.history_toggle_off_rounded,
                            label: 'History',
                            color: const Color(0xFF5C6BC0),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const FilteredTransactionsScreen(type: 'All'),
                                ),
                              ).then((_) => refreshData());
                            },
                          ),
                          _buildQuickActionButton(
                            icon: Icons.bar_chart_rounded,
                            label: 'Analytics',
                            color: const Color(0xFFAB47BC),
                            onTap: () {
                              // Switch to Statistics tab in bottom navbar
                              context.findAncestorStateOfType<BottomNavbarScreenState>()?.switchTab(1);
                            },
                          ),
                          _buildQuickActionButton(
                            icon: Icons.tune_rounded,
                            label: 'Settings',
                            color: const Color(0xFFFFA726),
                            onTap: _showSettings,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Transactions Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Transactions',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          if (displayTransactions.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const FilteredTransactionsScreen(type: 'All'),
                                  ),
                                ).then((_) => refreshData());
                              },
                              child: const Text('See all'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
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
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                )
              else if (displayTransactions.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 64,
                            color: AppColors.isDark(context)
                                ? AppColors.textMutedOf(context).withValues(alpha: 0.4)
                                : Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No transactions yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimaryOf(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + to add your first transaction',
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
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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
        ),
      ),
    );
  }

  Widget _buildCardTogglePill(int mode, String label) {
    final isSelected = _balanceViewMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _balanceViewMode = mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (mode == 1
                  ? AppColors.income
                  : mode == 2
                      ? AppColors.expense
                      : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? (mode == 0 ? Colors.black87 : Colors.white)
                : Colors.white.withValues(alpha: 0.7),
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required double value,
    required IconData icon,
    required Color color,
    required int mode,
  }) {
    final isSelected = _balanceViewMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _balanceViewMode = isSelected ? 0 : mode;
        });
      },
      onLongPress: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FilteredTransactionsScreen(
              type: label == 'Income' ? 'Income' : 'Expense',
            ),
          ),
        ).then((_) => refreshData());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    FormatUtils.formatCurrency(value, compact: false),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(TransactionModel txn) {
    final isIncome = txn.type.toLowerCase() == 'income';
    final catColor = AppColors.getCategoryColor(txn.category);
    final isAutoDetected = txn.autoDetected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.borderOf(context).withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: AppColors.cardShadowOf(context),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
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
                            Stack(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    IconHelper.getIcon(txn.icon),
                                    color: catColor,
                                    size: 20,
                                  ),
                                ),
                                if (isAutoDetected)
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2196F3),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.cardOf(context), width: 1.5),
                                      ),
                                      child: const Icon(
                                        Icons.auto_awesome,
                                        size: 8,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    txn.note?.isNotEmpty == true ? txn.note! : txn.category,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimaryOf(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceOf(context),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          txn.category,
                                          style: TextStyle(
                                            color: AppColors.textSecondaryOf(context),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _formatTime(txn.date),
                                        style: TextStyle(
                                          color: AppColors.textMutedOf(context),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${isIncome ? '+' : '-'}${FormatUtils.formatCurrency(txn.amount, compact: false)}',
                              style: TextStyle(
                                color: isIncome ? AppColors.income : AppColors.expense,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
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
        ),
      ),
    );
  }
}
