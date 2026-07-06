import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/repositories/transaction_repository.dart';
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
  late final TransactionRepository _repo;
  List<Map<String, Object?>> _allRows = [];
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
    _repo = TransactionRepository();

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
    _load();
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
      final rows = await _repo.getAll();
      if (!mounted) return;
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
      builder: (BuildContext context) {
        DateTime tempDate = _showingToday ? _selectedDate : _currentMonth;
        return Container(
          height: 300,
          color: Colors.white,
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

  String _formatTxDate(DateTime d) {
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

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
    final amountColor = isTxIncome ? AppColors.income : AppColors.expense;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TransactionDetailScreen(data: tx),
              ),
            );
            if (mounted) await _load();
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        amountColor.withValues(alpha: 0.15),
                        Colors.white,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    tx['icon'] != null
                        ? IconData(
                            tx['icon'] as int,
                            fontFamily: 'MaterialIcons',
                          )
                        : _iconForNote(tx['note'] as String?),
                    size: 24,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx['title'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tx['subtitle'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (isTxIncome ? '+' : '-') +
                          _formatCurrency(tx['amount'] as double),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: amountColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTxDate(tx['date'] as DateTime),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textLight,
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

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type.toLowerCase() == 'income';
    final isAll = widget.type.toLowerCase() == 'all';
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + 12,
                  16,
                  16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            widget.type,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Toggle
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
                                color: Colors.white.withValues(alpha: 0.15),
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
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
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
                                                    ? AppColors.primary
                                                    : Colors.white,
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
                                                    ? AppColors.primary
                                                    : Colors.white,
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
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.white,
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
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  color: Colors.white,
                                  size: 16,
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
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Total
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              _formatCurrency(_total),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
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

          // Page indicator
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
                        color: AppColors.primary.withValues(alpha: 0.9),
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
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No ${widget.type.toLowerCase()} transactions',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _showingToday
                  ? 'for ${_fullDateLabel()}'
                  : 'for ${_monthYearLabel()}',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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
