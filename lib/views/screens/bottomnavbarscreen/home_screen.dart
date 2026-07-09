import 'package:buddy/services/notification_service.dart';
import 'package:buddy/utils/images.dart';
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
      begin: -6.0,
      end: 6.0,
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
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(AppImages.curvedBackground, fit: BoxFit.cover),
          ),

          SafeArea(
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
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _greeting(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.cardBackground
                                              .withValues(alpha: 0.8),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _displayName,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.cardBackground,
                                        ),
                                        textAlign: TextAlign.start,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: Colors.transparent,
                                    isScrollControlled: true,
                                    builder: (context) => SettingsModal(
                                      onDataCleared: () => refreshData(),
                                    ),
                                  );
                                },
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.settings_rounded,
                                    size: 24,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Balance Card
                          AnimatedBuilder(
                            animation: _bobAnimation,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(0, _bobAnimation.value),
                                child: child,
                              );
                            },
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const FilteredTransactionsScreen(type: 'All'),
                                  ),
                                ).then((_) => refreshData());
                              },
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primary.withValues(alpha: 0.8),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: 0.3),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Current Balance',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      FormatUtils.formatCurrency(
                                        _totalBalance,
                                        compact: false,
                                      ),
                                      style: TextStyle(
                                        color: _totalBalance >= 0
                                            ? Colors.white
                                            : Colors.red.shade300,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
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
                          ),

                          const SizedBox(height: 24),

                          // Transactions Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Recent Transactions',
                                style: TextStyle(
                                  fontSize: 18,
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
                                    top: itemIndex == 0 ? 0 : 16,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade500,
                                      letterSpacing: 0.5,
                                    ),
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
        ],
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    FormatUtils.formatCurrency(value, compact: false),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
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
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
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
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        IconData(txn.icon, fontFamily: 'MaterialIcons'),
                        color: catColor,
                        size: 22,
                      ),
                    ),
                    if (isAutoDetected)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
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
                    children: [
                      Text(
                        txn.note?.isNotEmpty == true ? txn.note! : txn.category,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        txn.category,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isIncome ? '+' : '-'}${FormatUtils.formatCurrency(txn.amount, compact: false)}',
                      style: TextStyle(
                        color: isIncome ? AppColors.income : AppColors.expense,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(txn.date),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
