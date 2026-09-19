import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/views/screens/transaction_detail_screen.dart';

class FilteredTransactionsScreen extends StatefulWidget {
  final String type; // 'income', 'expense', or 'All'

  const FilteredTransactionsScreen({super.key, required this.type});

  @override
  State<FilteredTransactionsScreen> createState() =>
      _FilteredTransactionsScreenState();
}

class _FilteredTransactionsScreenState extends State<FilteredTransactionsScreen>
    with TickerProviderStateMixin {
  final FirestoreService _firestore = FirestoreService.instance;
  List<Map<String, dynamic>> _allRows = [];
  List<Map<String, dynamic>> _displayedTransactions = [];
  List<Map<String, dynamic>> _nextTransactions = [];
  DateTime _currentMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  double _total = 0;
  bool _showingToday = true;

  // Drag state for real-time preview
  double _dragOffset = 0.0;
  bool _isDragging = false;
  DateTime? _previewDate;
  DateTime? _previewMonth;
  bool _previewLoaded = false;

  // Animation controllers
  late AnimationController _slideController;
  late Animation<Offset> _currentSlideAnimation;
  late Animation<Offset> _nextSlideAnimation;
  bool _isTransitioning = false;
  bool _isSwipingNext = true;

  // Toggle animation properties
  double _togglePage = 0.0;
  bool _toggleDragging = false;
  double _toggleDragStartPage = 0.0;
  double _toggleAccumX = 0.0;

  // Page indicator animation
  late AnimationController _indicatorController;
  late Animation<double> _indicatorAnimation;

  @override
  void initState() {
    super.initState();
    _load();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _indicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _indicatorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _indicatorController, curve: Curves.easeInOut),
    );

    _updateSlideAnimations(true);
  }

  void _updateSlideAnimations(bool isNext) {
    _currentSlideAnimation =
        Tween<Offset>(
          begin: Offset.zero,
          end: Offset(isNext ? -1.0 : 1.0, 0),
        ).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _nextSlideAnimation =
        Tween<Offset>(
          begin: Offset(isNext ? 1.0 : -1.0, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _indicatorController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final txns = await _firestore.getAllTransactions();
      if (!mounted) return;
      final rows = txns.map((t) => <String, dynamic>{
        'amount': t.amount,
        'type': t.type,
        'date': t.date.toIso8601String(),
        'category': t.category,
        'icon': t.icon,
        'note': t.note,
        'id': t.id,
        'autoDetected': t.autoDetected,
      }).toList();
      setState(() {
        _allRows = rows;
        _isLoading = false;
      });
      _filterByMonth();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      debugPrint('Error loading transactions: $e');
    }
  }

  List<Map<String, dynamic>> _getFilteredTransactions(
    DateTime date,
    bool isToday,
  ) {
    final filtered = _allRows.where((r) {
      final type = (r['type'] as String?)?.toLowerCase().trim() ?? '';
      if (widget.type.toLowerCase().trim() != 'all' &&
          widget.type.toLowerCase().trim() != type) {
        return false;
      }

      final dateStr = r['date'] as String?;
      if (dateStr == null) return false;

      final dt = DateTime.tryParse(dateStr);
      if (dt == null) return false;

      if (isToday) {
        return dt.year == date.year &&
            dt.month == date.month &&
            dt.day == date.day;
      } else {
        return dt.year == date.year && dt.month == date.month;
      }
    }).toList();

    filtered.sort((a, b) {
      final dateA = DateTime.tryParse(a['date'] as String? ?? '');
      final dateB = DateTime.tryParse(b['date'] as String? ?? '');
      if (dateA == null || dateB == null) return 0;
      return dateB.compareTo(dateA);
    });

    return filtered.map((r) {
      final dt = DateTime.tryParse(r['date'] as String) ?? DateTime.now();
      final amt = (r['amount'] as num).toDouble();
      return {
        'type': r['type'],
        'title': (r['note'] as String?)?.isNotEmpty == true
            ? r['note']
            : r['category'],
        'subtitle': r['category'],
        'amount': amt,
        'time': _formatTime(dt),
        'date': dt,
        'category': r['category'],
        'note': r['note'],
        'avatarText': (r['category'] as String?)?.substring(0, 1) ?? '?',
        'icon': r['icon'],
        'id': r['id'],
        'autoDetected': r['autoDetected'] as bool? ?? false,
      };
    }).toList();
  }

  double _calculateTotal(List<Map<String, dynamic>> transactions) {
    double total = 0;
    for (var tx in transactions) {
      final type = (tx['type'] as String).toLowerCase().trim();
      final amt = tx['amount'] as double;
      if (type == 'income') {
        total += amt;
      } else if (type == 'expense') {
        total -= amt;
      }
    }
    return total;
  }

  void _filterByMonth() {
    final transactions = _getFilteredTransactions(
      _showingToday ? _selectedDate : _currentMonth,
      _showingToday,
    );

    setState(() {
      _displayedTransactions = transactions;
      _total = _calculateTotal(transactions);
    });
  }

  void _resetDragState() {
    _dragOffset = 0.0;
    _isDragging = false;
    _nextTransactions = [];
    _previewDate = null;
    _previewMonth = null;
    _previewLoaded = false;
  }

  // Real-time drag preview handlers
  void _onHorizontalDragStart(DragStartDetails details) {
    if (_isTransitioning) return;
    setState(() {
      _isDragging = true;
      _dragOffset = 0.0;
      _previewLoaded = false;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isTransitioning) return;

    setState(() {
      _dragOffset += details.delta.dx;

      // Load preview data when drag exceeds threshold
      if (_dragOffset.abs() > 30 && !_previewLoaded) {
        final isNext = _dragOffset < 0;

        if (_showingToday) {
          _previewDate = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day + (isNext ? 1 : -1),
          );
          _nextTransactions = _getFilteredTransactions(_previewDate!, true);
        } else {
          _previewMonth = DateTime(
            _currentMonth.year,
            _currentMonth.month + (isNext ? 1 : -1),
          );
          _nextTransactions = _getFilteredTransactions(_previewMonth!, false);
        }
        _previewLoaded = true;
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isTransitioning) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final threshold = screenWidth * 0.25;
    final velocity = details.primaryVelocity ?? 0;
    final velocityThreshold = 800;

    // Determine if swipe should complete
    final shouldComplete =
        _dragOffset.abs() > threshold || velocity.abs() > velocityThreshold;

    if (shouldComplete && _previewLoaded) {
      // Determine direction
      final isNext =
          _dragOffset < 0 ||
          (velocity.abs() > velocityThreshold && velocity < 0);
      _completeSwipeWithAnimation(isNext);
    } else {
      // Cancel the swipe
      setState(() {
        _resetDragState();
      });
    }
  }

  void _completeSwipeWithAnimation(bool isNext) {
    if (!_previewLoaded) return;

    HapticFeedback.mediumImpact();
    _indicatorController.forward(from: 0);

    // Recalculate target date/month and data to ensure correctness
    final DateTime? targetDate;
    final DateTime? targetMonth;
    final List<Map<String, dynamic>> targetTransactions;

    if (_showingToday) {
      targetDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + (isNext ? 1 : -1),
      );
      targetMonth = null;
      targetTransactions = _getFilteredTransactions(targetDate, true);
    } else {
      targetDate = null;
      targetMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month + (isNext ? 1 : -1),
      );
      targetTransactions = _getFilteredTransactions(targetMonth, false);
    }

    setState(() {
      _isTransitioning = true;
      _isSwipingNext = isNext;
      _isDragging = false;
      _nextTransactions = targetTransactions;
    });

    _updateSlideAnimations(isNext);
    _slideController.reset();
    _slideController.forward().then((_) {
      if (!mounted) return;

      setState(() {
        if (_showingToday && targetDate != null) {
          _selectedDate = targetDate;
        } else if (!_showingToday && targetMonth != null) {
          _currentMonth = targetMonth;
        }

        _displayedTransactions = targetTransactions;
        _total = _calculateTotal(targetTransactions);
        _isTransitioning = false;
        _resetDragState();
      });
      _slideController.reset();
    });
  }

  // Arrow button handlers (uses animation)
  void _changeMonth(bool isNext) {
    if (_isTransitioning || _isDragging) return;

    HapticFeedback.mediumImpact();
    _indicatorController.forward(from: 0);

    final nextMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + (isNext ? 1 : -1),
    );

    final nextTransactions = _getFilteredTransactions(nextMonth, false);

    setState(() {
      _isTransitioning = true;
      _isSwipingNext = isNext;
      _nextTransactions = nextTransactions;
    });

    _updateSlideAnimations(isNext);
    _slideController.reset();
    _slideController.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _currentMonth = nextMonth;
        _displayedTransactions = nextTransactions;
        _total = _calculateTotal(nextTransactions);
        _isTransitioning = false;
        _resetDragState();
      });
      _slideController.reset();
    });
  }

  void _changeDate(bool isNext) {
    if (_isTransitioning || _isDragging) return;

    HapticFeedback.mediumImpact();
    _indicatorController.forward(from: 0);

    final nextDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day + (isNext ? 1 : -1),
    );

    final nextTransactions = _getFilteredTransactions(nextDate, true);

    setState(() {
      _isTransitioning = true;
      _isSwipingNext = isNext;
      _nextTransactions = nextTransactions;
    });

    _updateSlideAnimations(isNext);
    _slideController.reset();
    _slideController.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _selectedDate = nextDate;
        _displayedTransactions = nextTransactions;
        _total = _calculateTotal(nextTransactions);
        _isTransitioning = false;
        _resetDragState();
      });
      _slideController.reset();
    });
  }

  void _showMonthPicker() {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext ctx) {
        DateTime tempDate = _showingToday ? _selectedDate : _currentMonth;
        return Container(
          height: 300,
          color: AppColors.cardOf(ctx),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).pop();
                        setState(() {
                          if (_showingToday) {
                            _selectedDate = tempDate;
                          } else {
                            _currentMonth = DateTime(
                              tempDate.year,
                              tempDate.month,
                            );
                          }
                        });
                        _filterByMonth();
                      },
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: _showingToday
                      ? CupertinoDatePickerMode.date
                      : CupertinoDatePickerMode.monthYear,
                  initialDateTime: tempDate,
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (DateTime newDate) {
                    HapticFeedback.selectionClick();
                    tempDate = newDate;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleView(int index) {
    if ((_showingToday && index == 0) || (!_showingToday && index == 1)) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _showingToday = (index == 0);
      _togglePage = index.toDouble();
      if (_showingToday) {
        _selectedDate = DateTime.now();
      } else {
        _currentMonth = DateTime.now();
      }
      _resetDragState();
    });
    _filterByMonth();
  }

  String _formatTime(DateTime d) {
    final hour = d.hour;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $ampm';
  }

  String _formatCurrency(double v) =>
      FormatUtils.formatCurrency(v, compact: true);



  String _monthYearLabel() {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[_currentMonth.month - 1]} ${_currentMonth.year}';
  }

  String _fullDateLabel() {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}';
  }

  IconData _iconForNote(String? note) {
    final n = (note ?? '').toLowerCase();
    if (n.contains('coffee') ||
        n.contains('cafe') ||
        n.contains('drink') ||
        n.contains('food') ||
        n.contains('snack')) {
      return Icons.fastfood_rounded;
    }
    if (n.contains('fuel') || n.contains('petrol') || n.contains('gas')) {
      return Icons.local_gas_station_rounded;
    }
    if (n.contains('uber') || n.contains('taxi') || n.contains('cab')) {
      return Icons.local_taxi_rounded;
    }
    if (n.contains('rent') || n.contains('home')) {
      return Icons.home_rounded;
    }
    if (n.contains('phone') || n.contains('mobile')) {
      return Icons.phone_android_rounded;
    }
    if (n.contains('netflix') ||
        n.contains('hotstar') ||
        n.contains('youtube') ||
        n.contains('movie')) {
      return Icons.movie_rounded;
    }
    if (n.contains('gym') || n.contains('fitness')) {
      return Icons.fitness_center_rounded;
    }
    if (n.contains('gift')) {
      return Icons.card_giftcard_rounded;
    }
    if (n.contains('refund')) {
      return Icons.reply_rounded;
    }
    if (n.contains('salary') ||
        n.contains('upwork') ||
        n.contains('payment') ||
        n.contains('pay')) {
      return Icons.payments_rounded;
    }
    if (n.contains('travel') || n.contains('flight') || n.contains('trip')) {
      return Icons.flight_rounded;
    }
    if (n.contains('shop') || n.contains('shopping') || n.contains('grocer')) {
      return Icons.shopping_bag_rounded;
    }
    if (n.contains('pet')) {
      return Icons.pets_rounded;
    }
    if (n.contains('medical') ||
        n.contains('doctor') ||
        n.contains('hospital')) {
      return Icons.medical_services_rounded;
    }
    if (n.contains('school') ||
        n.contains('tuition') ||
        n.contains('education')) {
      return Icons.school_rounded;
    }
    if (n.contains('game') || n.contains('esports')) {
      return Icons.sports_esports_rounded;
    }
    return Icons.receipt_long_rounded;
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx, bool isAll) {
    final txType = (tx['type'] as String).toLowerCase();
    final isTxIncome = txType == 'income';
    final category = (tx['category'] as String?) ?? 'Other';
    final catColor = AppColors.getCategoryColor(category);
    final isAutoDetected = tx['autoDetected'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.borderOf(context),
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
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TransactionDetailScreen(data: tx),
                          ),
                        );
                        if (mounted) await _load();
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
                                    color: catColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    tx['icon'] != null
                                        ? IconData(tx['icon'] as int, fontFamily: 'MaterialIcons') // ignore: non_const_argument_for_const_parameter
                                        : _iconForNote(tx['note'] as String?),
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
                                    (tx['title'] as String?)?.isNotEmpty == true ? tx['title'] as String : category,
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
                                          category,
                                          style: TextStyle(
                                            color: AppColors.textSecondaryOf(context),
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
                                                color: Colors.blue.shade400,
                                              ),
                                              const SizedBox(width: 2),
                                              Text(
                                                'Auto',
                                                style: TextStyle(
                                                  color: Colors.blue.shade400,
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
                                  '${isTxIncome ? '+' : '-'}${_formatCurrency(tx['amount'] as double)}',
                                  style: TextStyle(
                                    color: isTxIncome ? AppColors.income : AppColors.textPrimaryOf(context),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _formatTime(tx['date'] as DateTime),
                                  style: TextStyle(
                                    color: AppColors.textSecondaryOf(context),
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

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type.toLowerCase() == 'income';
    final isAll = widget.type.toLowerCase() == 'all';
    final screenWidth = MediaQuery.of(context).size.width;

    final accentColor = isAll
        ? AppColors.primary
        : (isIncome ? AppColors.income : AppColors.expense);

    final cardBgColor = isAll
        ? AppColors.primary.withValues(alpha: 0.08)
        : (isIncome ? AppColors.income.withValues(alpha: 0.08) : AppColors.expense.withValues(alpha: 0.08));

    final textTotalColor = isAll
        ? AppColors.primary
        : (isIncome ? AppColors.income : AppColors.expense);

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: AppColors.cardOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        title: Text(
          widget.type == 'All' ? 'All Transactions' : '${widget.type} Transactions',
          style: TextStyle(
            color: AppColors.textPrimaryOf(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            color: AppColors.borderOf(context),
            height: 1,
            thickness: 1,
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Filter controls & Summary card
              Container(
                color: AppColors.cardOf(context),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Toggle View (Today / Month)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final totalWidth = constraints.maxWidth * 0.7;
                        const itemCount = 2;
                        final itemWidth = totalWidth / itemCount;
                        final indicatorWidth = itemWidth - 4;

                        final animatedLeft =
                            (_toggleDragging
                                    ? _togglePage.clamp(0, itemCount - 1)
                                    : (_showingToday ? 0.0 : 1.0)) *
                                itemWidth +
                            2;

                        return Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (details) {
                              _toggleAccumX = 0;
                              setState(() {
                                _toggleDragging = true;
                                _toggleDragStartPage = _showingToday
                                    ? 0.0
                                    : 1.0;
                                _togglePage = _toggleDragStartPage;
                              });
                            },
                            onPanUpdate: (details) {
                              _toggleAccumX += details.delta.dx;
                              final deltaPages = _toggleAccumX / itemWidth;
                              final double newPage =
                                  (_toggleDragStartPage + deltaPages).clamp(
                                    0.0,
                                    1.0,
                                  );
                              setState(() {
                                _togglePage = newPage;
                              });
                            },
                            onPanEnd: (details) {
                              final target = _togglePage.round();
                              setState(() {
                                _toggleDragging = false;
                              });
                              _toggleView(target);
                            },
                            child: Container(
                              width: totalWidth,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceOf(context),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: animatedLeft,
                                    top: 2,
                                    width: indicatorWidth,
                                    height: 36,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      curve: Curves.easeOut,
                                      decoration: BoxDecoration(
                                        color: AppColors.cardOf(context),
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: AppColors.cardShadowOf(context),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: itemWidth,
                                        child: Center(
                                          child: GestureDetector(
                                            onTap: () => _toggleView(0),
                                            child: Text(
                                              'Today',
                                              style: TextStyle(
                                                color: _showingToday
                                                    ? accentColor
                                                    : AppColors.textSecondaryOf(context),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: Center(
                                          child: GestureDetector(
                                            onTap: () => _toggleView(1),
                                            child: Text(
                                              'This Month',
                                              style: TextStyle(
                                                color: !_showingToday
                                                    ? accentColor
                                                    : AppColors.textSecondaryOf(context),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Date/Month navigation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: (_isTransitioning || _isDragging)
                              ? null
                              : () => _showingToday
                                    ? _changeDate(false)
                                    : _changeMonth(false),
                          icon: Icon(
                            Icons.chevron_left_rounded,
                            color: (_isTransitioning || _isDragging)
                                ? AppColors.textLightOf(context)
                                : AppColors.textPrimaryOf(context),
                            size: 32,
                          ),
                        ),
                        GestureDetector(
                          onTap: _showMonthPicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.borderOf(context),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _showingToday
                                      ? _fullDateLabel()
                                      : _monthYearLabel(),
                                  style: TextStyle(
                                    color: AppColors.textPrimaryOf(context),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.calendar_today_rounded,
                                  color: AppColors.textSecondaryOf(context),
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: (_isTransitioning || _isDragging)
                              ? null
                              : () => _showingToday
                                    ? _changeDate(true)
                                    : _changeMonth(true),
                          icon: Icon(
                            Icons.chevron_right_rounded,
                            color: (_isTransitioning || _isDragging)
                                ? AppColors.textLightOf(context)
                                : AppColors.textPrimaryOf(context),
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Total Summary
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              color: AppColors.textSecondaryOf(context),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              _formatCurrency(_total),
                              style: TextStyle(
                                color: textTotalColor,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Swipable transactions list with real-time preview
              Expanded(
                child: GestureDetector(
                  onHorizontalDragStart: _onHorizontalDragStart,
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: Stack(
                    children: [
                      // Current transactions (with drag offset or animation)
                      if (!_isTransitioning)
                        Transform.translate(
                          offset: Offset(_dragOffset, 0),
                          child: _buildContentView(
                            isAll,
                            isIncome,
                            _displayedTransactions,
                          ),
                        )
                      else
                        SlideTransition(
                          position: _currentSlideAnimation,
                          child: _buildContentView(
                            isAll,
                            isIncome,
                            _displayedTransactions,
                          ),
                        ),

                      // Next/Previous transactions preview
                      if (_isDragging && _previewLoaded)
                        Transform.translate(
                          offset: Offset(
                            _dragOffset < 0
                                ? screenWidth + _dragOffset
                                : -screenWidth + _dragOffset,
                            0,
                          ),
                          child: _buildContentView(
                            isAll,
                            isIncome,
                            _nextTransactions,
                          ),
                        ),

                      // Next content sliding in during animation
                      if (_isTransitioning)
                        SlideTransition(
                          position: _nextSlideAnimation,
                          child: _buildContentView(
                            isAll,
                            isIncome,
                            _nextTransactions,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Page indicator overlay
          AnimatedBuilder(
            animation: _indicatorAnimation,
            builder: (context, child) {
              if (_indicatorAnimation.value == 0) {
                return const SizedBox.shrink();
              }

              return Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: 1.0 - _indicatorAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isSwipingNext
                                ? Icons.arrow_forward_rounded
                                : Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _showingToday
                                ? _fullDateLabel()
                                : _monthYearLabel(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContentView(
    bool isAll,
    bool isIncome,
    List<Map<String, dynamic>> transactions,
  ) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAll
                  ? Icons.receipt_long_rounded
                  : (isIncome
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded),
              size: 80,
              color: AppColors.textLightOf(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No ${widget.type.toLowerCase()} transactions',
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textSecondaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _showingToday
                  ? 'for ${_fullDateLabel()}'
                  : 'for ${_monthYearLabel()}',
              style: TextStyle(fontSize: 14, color: AppColors.textLightOf(context)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final tx = transactions[index];
        return _buildTransactionCard(tx, isAll);
      },
    );
  }
}
