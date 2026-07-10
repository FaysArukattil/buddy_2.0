import 'package:buddy/services/notification_service.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/views/screens/transaction_detail_screen.dart';
import 'package:buddy/views/screens/filtered_transactions_screen.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/views/widgets/setting_modal.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:buddy/views/screens/add_transaction_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/bottom_navbar_screen.dart';

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
    NotificationService.requestNotificationAccess();
    NotificationService.startListening();

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

    // Listen to Firestore transactions in real-time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
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
    }
  }

  void _startListening() {
    try {
      _txnSubscription?.cancel();
      _txnSubscription =
          FirestoreService.instance.getTransactionsStream().listen(
        (transactions) {
          if (!mounted) return;

          final now = DateTime.now();
          double monthIncome = 0;
          double monthExpense = 0;

          for (final txn in transactions) {
            if (txn.date.year == now.year && txn.date.month == now.month) {
              if (txn.type == 'income') {
                monthIncome += txn.amount;
              } else {
                monthExpense += txn.amount;
              }
            }
          }

          setState(() {
            _transactions = transactions;
            _income = monthIncome;
            _expenses = monthExpense;
            _totalBalance = monthIncome - monthExpense;
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

  Future<void> refreshData() async {
    _loadUser();
    // Stream auto-refreshes, but we can restart it
    _startListening();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    final savedName = prefs.getString('name')?.trim() ?? '';
    final email = user?.email ?? prefs.getString('email')?.trim() ?? '';

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
      setState(() => _displayName = displayName);
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
              color: AppColors.background,
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
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
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

    // Group transactions by date
    final grouped = <String, List<TransactionModel>>{};
    for (final txn in _transactions) {
      final header = _getDateHeader(txn.date);
      grouped.putIfAbsent(header, () => []).add(txn);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refreshData,
          color: AppColors.primary,
          backgroundColor: Colors.white,
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
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _displayName,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
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
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade100,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.settings_rounded,
                                    size: 20,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => context.findAncestorStateOfType<BottomNavbarScreenState>()?.switchTab(2),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'CURRENT BALANCE',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
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
                              const SizedBox(height: 2),
                              Text(
                                FormatUtils.formatCurrency(
                                  _totalBalance,
                                  compact: false,
                                ),
                                style: TextStyle(
                                  color: _totalBalance >= 0
                                      ? Colors.white
                                      : Colors.red.shade300,
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
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatTile(
                                      label: 'Expenses',
                                      value: _expenses,
                                      icon: Icons.arrow_downward_rounded,
                                      color: AppColors.expense,
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
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
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
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const FilteredTransactionsScreen(type: 'Expense'),
                                ),
                              ).then((_) => refreshData());
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
                          const Text(
                            'Recent Transactions',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (_transactions.isNotEmpty)
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
              else if (_transactions.isEmpty)
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
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No transactions yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + to add your first transaction',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
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
                                      color: Colors.grey.shade500,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Divider(
                                      color: Colors.grey.shade200,
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

  Widget _buildStatTile({
    required String label,
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () {
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
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
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
                                    IconData(txn.icon, fontFamily: 'MaterialIcons'), // ignore: non_const_argument_for_const_parameter
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
                                        border: Border.all(color: Colors.white, width: 1.5),
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
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
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          txn.category,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (isAutoDetected) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0xFF2196F3).withValues(alpha: 0.3),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.auto_awesome,
                                                size: 9,
                                                color: Colors.blue.shade600,
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                'Auto',
                                                style: TextStyle(
                                                  color: Colors.blue.shade600,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${isIncome ? '+' : '-'}${FormatUtils.formatCurrency(txn.amount, compact: false)}',
                                  style: TextStyle(
                                    color: isIncome ? AppColors.income : AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _formatTime(txn.date),
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
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
        ),
      ),
    );
  }
}
