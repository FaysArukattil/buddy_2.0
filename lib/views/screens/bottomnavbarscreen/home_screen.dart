import 'package:buddy/services/notification_service.dart';
import 'package:buddy/utils/images.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/views/screens/transaction_detail_screen.dart';
import 'package:buddy/views/screens/filtered_transactions_screen.dart';
import 'package:buddy/repositories/transaction_repository.dart';
import 'package:buddy/views/widgets/setting_modal.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final List<Map<String, dynamic>> _transactions = [];
  late final TransactionRepository _repo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 HOME SCREEN INITIALIZED');
    NotificationService.requestNotificationAccess();
    NotificationService.startListening();

    // Add lifecycle observer to detect app resume
    WidgetsBinding.instance.addObserver(this);

    _loadUser();
    _repo = TransactionRepository();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _bobAnimation = Tween<double>(
      begin: -6.0,
      end: 6.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);

    // Load data after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshFromDb();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Called when app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 HOME SCREEN: App resumed - refreshing data');
      _refreshAll(); // Refresh everything including name
    }
  }

  // Public method for external refresh
  Future<void> refreshData() async {
    debugPrint('🔄 HOME SCREEN: External refresh requested');
    await _refreshAll();
  }

  // NEW: Refresh everything (name + transactions)
  Future<void> _refreshAll() async {
    await Future.wait([_loadUser(), _refreshFromDb()]);
  }

  Future<void> _refreshFromDb() async {
    if (!mounted) return;

    debugPrint('📊 HOME SCREEN: Loading transactions...');

    try {
      // Get all transactions from database
      final rows = await _repo.getAll();
      debugPrint('📖 Found ${rows.length} total transactions');

      if (!mounted) return;

      // Calculate current month totals
      final now = DateTime.now();
      double monthIncome = 0;
      double monthExpense = 0;

      // Process all transactions
      final List<Map<String, dynamic>> allTransactions = [];

      for (final row in rows) {
        // Parse transaction data
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        final type = (row['type'] as String?)?.toLowerCase() ?? '';
        final dateStr = row['date'] as String? ?? '';
        final date = DateTime.tryParse(dateStr) ?? now;

        // Check if transaction is in current month
        if (date.year == now.year && date.month == now.month) {
          if (type == 'income') {
            monthIncome += amount;
          } else if (type == 'expense') {
            monthExpense += amount;
          }
        }

        // Add to transaction list
        allTransactions.add({
          'id': row['id'],
          'type': row['type'],
          'title': (row['note'] as String?)?.isNotEmpty == true
              ? row['note']
              : row['category'],
          'subtitle': row['category'],
          'amount': amount,
          'time': _formatTime(date),
          'date': date,
          'category': row['category'],
          'note': row['note'],
          'avatarText': (row['category'] as String?)?.isNotEmpty == true
              ? (row['category'] as String).substring(0, 1).toUpperCase()
              : '?',
          'icon': row['icon'],
          'auto_detected': row['auto_detected'] == 1,
        });
      }

      // Sort transactions by date (newest first)
      allTransactions.sort((a, b) {
        final dateA = a['date'] as DateTime;
        final dateB = b['date'] as DateTime;
        return dateB.compareTo(dateA);
      });

      // Calculate balance
      final balance = monthIncome - monthExpense;

      debugPrint('💰 Current Month Summary:');
      debugPrint('   Income: ₹$monthIncome');
      debugPrint('   Expense: ₹$monthExpense');
      debugPrint('   Balance: ₹$balance');

      // Update UI
      if (mounted) {
        setState(() {
          _transactions.clear();
          _transactions.addAll(allTransactions);
          _income = monthIncome;
          _expenses = monthExpense;
          _totalBalance = balance;
          _isLoading = false;
        });

        debugPrint('✅ UI Updated Successfully');
      }
    } catch (e) {
      debugPrint('❌ Error loading transactions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    // Get saved name from SharedPreferences
    final savedName = prefs.getString('name')?.trim() ?? '';

    // Get email from Firebase Auth first, then fallback to SharedPreferences
    final email = user?.email ?? prefs.getString('email')?.trim() ?? '';

    debugPrint('👤 Loading user...');
    debugPrint('   Saved Name: $savedName');
    debugPrint('   Email: $email');
    debugPrint('   Firebase Display Name: ${user?.displayName}');

    // Use the same logic as ProfileScreen to generate display name
    String displayName = savedName;

    // If no saved name, try Firebase displayName (from Google sign-in)
    if (displayName.isEmpty && user?.displayName != null) {
      displayName = user!.displayName!;
    }

    // If still empty, generate from email
    if (displayName.isEmpty && email.isNotEmpty) {
      displayName = email.contains('@') ? email.split('@').first : email;
      if (displayName.isNotEmpty) {
        displayName = displayName[0].toUpperCase() + displayName.substring(1);
      }
    }

    // Fallback to 'Guest' if still empty
    if (displayName.isEmpty) {
      displayName = 'Guest';
    }

    debugPrint('👤 Final display name: $displayName');

    if (mounted) {
      setState(() {
        _displayName = displayName;
      });
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

  IconData _iconForNote(String? note) {
    final n = (note ?? '').toLowerCase();
    if (n.contains('coffee') || n.contains('cafe') || n.contains('food')) {
      return Icons.fastfood_rounded;
    }
    if (n.contains('fuel') || n.contains('petrol')) {
      return Icons.local_gas_station_rounded;
    }
    if (n.contains('uber') || n.contains('taxi')) {
      return Icons.local_taxi_rounded;
    }
    if (n.contains('rent') || n.contains('home')) {
      return Icons.home_rounded;
    }
    if (n.contains('salary') || n.contains('payment')) {
      return Icons.payments_rounded;
    }
    if (n.contains('shopping')) {
      return Icons.shopping_bag_rounded;
    }
    return Icons.receipt_long_rounded;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
              onRefresh: _refreshAll,
              color: AppColors.primary,
              backgroundColor: Colors.white,
              displacement: 60, // Distance from top before indicator appears
              strokeWidth: 3.0,
              edgeOffset: 0, // Start detecting from the very top
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
                          // Header with Settings Icon
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Greeting and Name
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                              // Settings Icon
                              IconButton(
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: Colors.transparent,
                                    isScrollControlled: true,
                                    builder: (context) => SettingsModal(
                                      onDataCleared: () {
                                        _refreshAll();
                                      },
                                    ),
                                  );
                                },
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
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
                                        const FilteredTransactionsScreen(
                                          type: 'All',
                                        ),
                                  ),
                                ).then((_) => _refreshAll());
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
                                      color: AppColors.primary.withValues(
                                        alpha: 0.3,
                                      ),
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

                          // Transactions Section
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
                                            const FilteredTransactionsScreen(
                                              type: 'All',
                                            ),
                                      ),
                                    ).then((_) => _refreshAll());
                                  },
                                  child: const Text('See all'),
                                ),
                            ],
                          ),

                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),

                  // Transaction List or Loading/Empty State
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
                                color: Colors.grey.shade400,
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
                                'Tap + to add your first transaction\nor enable notification access',
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final tx = _transactions[index];
                          return _buildTransactionTile(tx);
                        }, childCount: _transactions.length),
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
        ).then((_) => _refreshAll());
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

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final isIncome = (tx['type'] as String).toLowerCase() == 'income';
    final color = isIncome ? AppColors.income : AppColors.expense;
    final isAutoDetected = tx['auto_detected'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TransactionDetailScreen(data: tx),
              ),
            ).then((_) => _refreshAll());
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
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        tx['icon'] != null
                            ? IconData(
                                tx['icon'] as int,
                                fontFamily: 'MaterialIcons',
                              )
                            : _iconForNote(tx['note'] as String?),
                        color: color,
                        size: 24,
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
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 10,
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
                        tx['title'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        tx['subtitle'] as String,
                        style: TextStyle(
                          color: Colors.grey.shade600,
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
                      '${isIncome ? '+' : '-'}${FormatUtils.formatCurrency(tx['amount'] as double, compact: false)}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      tx['time'] as String,
                      style: TextStyle(
                        color: Colors.grey.shade500,
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
