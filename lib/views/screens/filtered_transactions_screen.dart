import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/utils/icon_helper.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/views/screens/transaction_detail_screen.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class FilteredTransactionsScreen extends StatefulWidget {
  final String type; // 'Income', 'Expense', or 'All'

  const FilteredTransactionsScreen({super.key, required this.type});

  @override
  State<FilteredTransactionsScreen> createState() =>
      _FilteredTransactionsScreenState();
}

class _FilteredTransactionsScreenState extends State<FilteredTransactionsScreen> {
  final FirestoreService _firestore = FirestoreService.instance;
  List<Map<String, dynamic>> _allRows = [];
  bool _isLoading = true;
  bool _showingToday = true;
  double _total = 0;

  // Base anchors for infinite smooth swiping
  static const int _baseIndex = 5000;
  late final DateTime _anchorDate;
  late final DateTime _anchorMonth;

  DateTime _selectedDate = DateTime.now();
  DateTime _currentMonth = DateTime.now();

  late final PageController _dayController;
  late final PageController _monthController;

  // Toggle animation properties for Today / This Month pill
  double _togglePage = 0.0;
  bool _toggleDragging = false;
  double _toggleDragStartPage = 0.0;
  double _toggleAccumX = 0.0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchorDate = DateTime(now.year, now.month, now.day);
    _anchorMonth = DateTime(now.year, now.month, 1);
    _selectedDate = _anchorDate;
    _currentMonth = _anchorMonth;

    _dayController = PageController(initialPage: _baseIndex);
    _monthController = PageController(initialPage: _baseIndex);

    _load();
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  DateTime _getDateForIndex(int index) {
    final offset = index - _baseIndex;
    return DateTime(_anchorDate.year, _anchorDate.month, _anchorDate.day + offset);
  }

  int _getIndexForDate(DateTime dt) {
    final d1 = DateTime(dt.year, dt.month, dt.day);
    final d2 = _anchorDate;
    return _baseIndex + d1.difference(d2).inDays;
  }

  DateTime _getMonthForIndex(int index) {
    final offset = index - _baseIndex;
    return DateTime(_anchorMonth.year, _anchorMonth.month + offset, 1);
  }

  int _getIndexForMonth(DateTime dt) {
    final offset = (dt.year - _anchorMonth.year) * 12 + (dt.month - _anchorMonth.month);
    return _baseIndex + offset;
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
        'auto_detected': t.autoDetected,
        'notificationSource': t.notificationSource,
      }).toList();

      setState(() {
        _allRows = rows;
        _isLoading = false;
        _updateTotal();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      debugPrint('Error loading transactions: $e');
    }
  }

  List<Map<String, dynamic>> _getFilteredTransactions(
    DateTime target,
    bool isToday,
  ) {
    final targetType = widget.type.toLowerCase().trim();
    final filtered = _allRows.where((r) {
      final type = (r['type'] as String?)?.toLowerCase().trim() ?? '';
      if (targetType != 'all' && targetType != type) {
        return false;
      }

      final dateStr = r['date'] as String?;
      if (dateStr == null) return false;

      final dt = DateTime.tryParse(dateStr);
      if (dt == null) return false;

      if (isToday) {
        return dt.year == target.year &&
            dt.month == target.month &&
            dt.day == target.day;
      } else {
        return dt.year == target.year && dt.month == target.month;
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
      final rawNote = (r['note'] as String?)?.trim();
      final cleanNote = TransactionModel.cleanNoteText(rawNote);
      final category = (r['category'] as String?) ?? 'Other';
      final title = (cleanNote != null && cleanNote.isNotEmpty)
          ? cleanNote
          : ((rawNote != null && rawNote.isNotEmpty) ? rawNote : category);
      return {
        'type': r['type'],
        'title': title,
        'subtitle': category,
        'amount': amt,
        'time': _formatTime(dt),
        'date': dt,
        'category': category,
        'note': cleanNote ?? r['note'],
        'avatarText': category.isNotEmpty ? category.substring(0, 1) : '?',
        'icon': r['icon'],
        'id': r['id'],
        'autoDetected': r['autoDetected'] as bool? ?? false,
        'auto_detected': r['autoDetected'] as bool? ?? false,
        'notificationSource': r['notificationSource'],
      };
    }).toList();
  }

  double _calculateTotal(List<Map<String, dynamic>> transactions) {
    double total = 0;
    for (var tx in transactions) {
      final type = (tx['type'] as String).toLowerCase().trim();
      final amt = (tx['amount'] as num).toDouble();
      if (type == 'income') {
        total += amt;
      } else if (type == 'expense') {
        total -= amt;
      }
    }
    return total;
  }

  void _updateTotal() {
    final list = _getFilteredTransactions(
      _showingToday ? _selectedDate : _currentMonth,
      _showingToday,
    );
    _total = _calculateTotal(list);
  }

  void _changeDate(bool isNext) {
    if (!_dayController.hasClients) return;
    HapticFeedback.selectionClick();
    if (isNext) {
      _dayController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _dayController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _changeMonth(bool isNext) {
    if (!_monthController.hasClients) return;
    HapticFeedback.selectionClick();
    if (isNext) {
      _monthController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _monthController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
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
        _selectedDate = _anchorDate;
        if (_dayController.hasClients) {
          _dayController.jumpToPage(_baseIndex);
        }
      } else {
        _currentMonth = _anchorMonth;
        if (_monthController.hasClients) {
          _monthController.jumpToPage(_baseIndex);
        }
      }
      _updateTotal();
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
                            final idx = _getIndexForDate(tempDate);
                            if (_dayController.hasClients) {
                              _dayController.jumpToPage(idx);
                            }
                          } else {
                            _currentMonth = DateTime(tempDate.year, tempDate.month, 1);
                            final idx = _getIndexForMonth(_currentMonth);
                            if (_monthController.hasClients) {
                              _monthController.jumpToPage(idx);
                            }
                          }
                          _updateTotal();
                        });
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
                  maximumDate: DateTime.now().add(const Duration(days: 365)),
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

  String _formatTime(DateTime d) {
    final hour = d.hour;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $ampm';
  }

  String _formatCurrency(double v) =>
      FormatUtils.formatCurrency(v, compact: true);

  String _formatMonthYear(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  String _formatFullDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
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

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final txType = (tx['type'] as String).toLowerCase().trim();
    final isTxIncome = txType == 'income';
    final category = (tx['category'] as String?) ?? 'Other';
    final catColor = AppColors.getCategoryColor(category);
    final isAutoDetected = tx['autoDetected'] as bool? ?? false;
    final title = (tx['title'] as String?)?.isNotEmpty == true
        ? tx['title'] as String
        : category;

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
                                    tx['icon'] != null
                                        ? IconHelper.getIcon(tx['icon'])
                                        : _iconForNote(tx['note'] as String?),
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
                                              category,
                                              style: TextStyle(
                                                color: catColor,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            tx['time'] as String? ?? '',
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
                                      '${isTxIncome ? '+' : '-'}${_formatCurrency((tx['amount'] as num).toDouble())}',
                                      style: TextStyle(
                                        color: isTxIncome ? AppColors.income : AppColors.expense,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15.5,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isTxIncome ? 'Income' : 'Expense',
                                      style: TextStyle(
                                        color: isTxIncome
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

  Widget _buildPageContent(
    List<Map<String, dynamic>> transactions,
    DateTime pageTarget, {
    required bool isToday,
  }) {
    if (_isLoading) {
      return BuddyLoadingIndicator.centered();
    }

    if (transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.type.toLowerCase() == 'income'
                    ? Icons.trending_up_rounded
                    : (widget.type.toLowerCase() == 'expense'
                        ? Icons.trending_down_rounded
                        : Icons.receipt_long_rounded),
                size: 72,
                color: AppColors.isDark(context)
                    ? AppColors.textMutedOf(context).withValues(alpha: 0.35)
                    : Colors.grey.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                widget.type.toLowerCase() == 'all'
                    ? 'No transactions'
                    : 'No ${widget.type.toLowerCase()} transactions',
                style: TextStyle(
                  fontSize: 17,
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isToday
                    ? 'for ${_formatFullDate(pageTarget)}'
                    : 'for ${_formatMonthYear(pageTarget)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final tx = transactions[index];
        return _buildTransactionCard(tx);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type.toLowerCase() == 'income';
    final isAll = widget.type.toLowerCase() == 'all';

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
      body: Column(
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
                            _toggleDragStartPage = _showingToday ? 0.0 : 1.0;
                            _togglePage = _toggleDragStartPage;
                          });
                        },
                        onPanUpdate: (details) {
                          _toggleAccumX += details.delta.dx;
                          final deltaPages = _toggleAccumX / itemWidth;
                          final double newPage =
                              (_toggleDragStartPage + deltaPages).clamp(0.0, 1.0);
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
                                  duration: const Duration(milliseconds: 120),
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
                // Date/Month navigation with chevron buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => _showingToday ? _changeDate(false) : _changeMonth(false),
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: AppColors.textPrimaryOf(context),
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
                                  ? _formatFullDate(_selectedDate)
                                  : _formatMonthYear(_currentMonth),
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
                      onPressed: () => _showingToday ? _changeDate(true) : _changeMonth(true),
                      icon: Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textPrimaryOf(context),
                        size: 32,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Total Summary Card
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

          // High-performance, buttery-smooth swipable PageView
          Expanded(
            child: _showingToday
                ? PageView.builder(
                    controller: _dayController,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final pageDate = _getDateForIndex(index);
                      final txns = _getFilteredTransactions(pageDate, true);
                      return _buildPageContent(txns, pageDate, isToday: true);
                    },
                    onPageChanged: (index) {
                      final newDate = _getDateForIndex(index);
                      setState(() {
                        _selectedDate = newDate;
                        _total = _calculateTotal(_getFilteredTransactions(newDate, true));
                      });
                    },
                  )
                : PageView.builder(
                    controller: _monthController,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final pageMonth = _getMonthForIndex(index);
                      final txns = _getFilteredTransactions(pageMonth, false);
                      return _buildPageContent(txns, pageMonth, isToday: false);
                    },
                    onPageChanged: (index) {
                      final newMonth = _getMonthForIndex(index);
                      setState(() {
                        _currentMonth = newMonth;
                        _total = _calculateTotal(_getFilteredTransactions(newMonth, false));
                      });
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
