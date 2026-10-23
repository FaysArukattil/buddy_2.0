import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
// ignore: depend_on_referenced_packages
import 'package:fl_chart/fl_chart.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/utils/icon_helper.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/pdf_service.dart';
import 'package:intl/intl.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';
import 'package:buddy/views/widgets/buddy_refresh_control.dart';
import 'package:buddy/services/preference_service.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => StatisticsScreenState();
}

class StatisticsScreenState extends State<StatisticsScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  int _selectedTab = 2;
  String _type = 'Expense';
  final List<String> _tabs = const ['Day', 'Week', 'Month', 'Year'];
  bool _isDownloading = false;
  DateTime _selectedDate = DateTime.now();

  // Scroll controller for overscroll effect
  final ScrollController _scrollController = ScrollController();

  // Chart view mode: 0 = Smooth Area Curve, 1 = Modern Rounded Bars, 2 = Category Donut Breakdown
  int _chartViewMode = 0;
  int _touchedPieIndex = -1;
  int? _touchedChartIndex;

  // Debt filter preference (matches HomeScreen: "On Home" vs "Separate")
  bool _includeDebtsInHome = true;

  // Swipe gesture tracking
  double _tabPage = 2.0;
  bool _tabDragging = false;
  double _tabDragStartPage = 0;
  double _tabDragStartX = 0;

  double _typePage = 0;
  bool _typeDragging = false;
  double _typeDragStartPage = 0;
  double _typeDragStartX = 0;

  final FirestoreService _firestore = FirestoreService.instance;
  List<Map<String, dynamic>> _rows = [];

  /// Returns rows filtered by debt preference (excludes Lending & Borrowing unless On Home is used)
  List<Map<String, dynamic>> get _activeRows {
    if (_includeDebtsInHome) return _rows;
    return _rows.where((r) {
      final cat = r['category'] as String?;
      return cat != 'Lending' && cat != 'Borrowing';
    }).toList();
  }

  // Optimized cache system
  List<double> _cachedPoints = [];
  List<String> _cachedLabels = [];
  double _cachedTotal = 0.0;
  List<Map<String, dynamic>> _cachedTopCategories = [];
  String _cacheKey = '';
  bool _isComputing = false;
  Timer? _debounceTimer;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _includeDebtsInHome = PreferenceService.includeDebtsInHome;
    PreferenceService.includeDebtsInHomeNotifier.addListener(_onDebtPrefChanged);
    if (FirestoreService.cachedTransactions.isNotEmpty) {
      final txns = FirestoreService.cachedTransactions;
      _rows = txns.map((t) => <String, dynamic>{
        'amount': t.amount,
        'type': t.type,
        'date': t.date.toIso8601String(),
        'category': t.category,
        'icon': t.icon,
        'note': t.note,
        'id': t.id,
      }).toList();
      _isLoading = false;
      _scheduleComputation();
    } else {
      _load();
    }
  }

  void _onDebtPrefChanged() {
    final val = PreferenceService.includeDebtsInHome;
    if (_includeDebtsInHome != val) {
      if (mounted) {
        setState(() => _includeDebtsInHome = val);
      }
      _scheduleComputation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    PreferenceService.includeDebtsInHomeNotifier.removeListener(_onDebtPrefChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    debugPrint('📊 STATISTICS: Loading transactions...');
    try {
      final txns = await _firestore.getAllTransactions(forceRefresh: forceRefresh);
      debugPrint('📊 STATISTICS: Loaded ${txns.length} transactions');
      // Convert to maps for backward compat with computation methods
      final rows = txns.map((t) => <String, dynamic>{
        'amount': t.amount,
        'type': t.type,
        'date': t.date.toIso8601String(),
        'category': t.category,
        'icon': t.icon,
        'note': t.note,
        'id': t.id,
      }).toList();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
      _scheduleComputation();
    } catch (e) {
      debugPrint('❌ STATISTICS: Error loading transactions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> refreshData() async {
    debugPrint('🔄 STATISTICS: Manual refresh triggered');
    await _load(forceRefresh: true);
  }

  void _scheduleComputation() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      _computeDataAsync();
    });
  }

  Future<void> _computeDataAsync() async {
    if (_isComputing) return;

    final newKey = _getCacheKey();
    if (newKey == _cacheKey) return;

    setState(() => _isComputing = true);

    await Future.microtask(() {
      final points = _computePoints();
      final labels = _computeLabels();
      final total = points.fold<double>(0.0, (sum, val) => sum + val);
      final topCategories = _computeTopCategories();

      if (mounted) {
        setState(() {
          _cacheKey = newKey;
          _cachedPoints = points;
          _cachedLabels = labels;
          _cachedTotal = total;
          _cachedTopCategories = topCategories;
          _isComputing = false;
        });
      }
    });
  }

  String _getCacheKey() {
    return '$_selectedTab-$_type-${_selectedDate.toString()}-${_rows.length}-$_includeDebtsInHome';
  }

  List<double> _computePoints() {
    final isIncome = _type.toLowerCase() == 'income';
    final now = _selectedDate;

    switch (_selectedTab) {
      case 0: // Day: 24 hours
        final buckets = List<double>.filled(24, 0);
        for (final r in _activeRows) {
          final type = (r['type'] as String).toLowerCase().trim();
          if ((isIncome && type != 'income') ||
              (!isIncome && type != 'expense')) {
            continue;
          }
          final dt = DateTime.tryParse(r['date'] as String);
          if (dt == null) continue;
          if (dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day) {
            buckets[dt.hour] += (r['amount'] as num).toDouble();
          }
        }
        return buckets;

      case 1: // Week: Mon..Sun
        final buckets = List<double>.filled(7, 0);
        final startOfWeek = now.subtract(Duration(days: (now.weekday - 1) % 7));
        final start = DateTime(
          startOfWeek.year,
          startOfWeek.month,
          startOfWeek.day,
        );
        final end = start.add(const Duration(days: 7));

        for (final r in _activeRows) {
          final type = (r['type'] as String).toLowerCase().trim();
          if ((isIncome && type != 'income') ||
              (!isIncome && type != 'expense')) {
            continue;
          }
          final dt = DateTime.tryParse(r['date'] as String);
          if (dt == null) continue;
          if (dt.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
              dt.isBefore(end)) {
            final idx = (dt.weekday - 1) % 7;
            buckets[idx] += (r['amount'] as num).toDouble();
          }
        }
        return buckets;

      case 2: // Month: 1..N days
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        final buckets = List<double>.filled(daysInMonth, 0);
        for (final r in _activeRows) {
          final type = (r['type'] as String).toLowerCase().trim();
          if ((isIncome && type != 'income') ||
              (!isIncome && type != 'expense')) {
            continue;
          }
          final dt = DateTime.tryParse(r['date'] as String);
          if (dt == null) continue;
          if (dt.year == now.year && dt.month == now.month) {
            buckets[dt.day - 1] += (r['amount'] as num).toDouble();
          }
        }
        return buckets;

      default: // Year: Jan..Dec
        final buckets = List<double>.filled(12, 0);
        for (final r in _activeRows) {
          final type = (r['type'] as String).toLowerCase().trim();
          if ((isIncome && type != 'income') ||
              (!isIncome && type != 'expense')) {
            continue;
          }
          final dt = DateTime.tryParse(r['date'] as String);
          if (dt == null) continue;
          if (dt.year == now.year) {
            buckets[dt.month - 1] += (r['amount'] as num).toDouble();
          }
        }
        return buckets;
    }
  }

  List<String> _computeLabels() {
    switch (_selectedTab) {
      case 0:
        return List.generate(24, (i) => '$i:00');
      case 1:
        return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      case 2:
        final now = _selectedDate;
        final days = DateTime(now.year, now.month + 1, 0).day;
        return List.generate(days, (i) => '${i + 1}');
      default:
        return const [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
    }
  }

  bool _isDateInCurrentPeriod(DateTime dt) {
    final now = _selectedDate;
    switch (_selectedTab) {
      case 0: // Day: today or selected day
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      case 1: // Week: Mon..Sun
        final startOfWeek = now.subtract(Duration(days: (now.weekday - 1) % 7));
        final start = DateTime(
          startOfWeek.year,
          startOfWeek.month,
          startOfWeek.day,
        );
        final end = start.add(const Duration(days: 7));
        return dt.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
            dt.isBefore(end);
      case 2: // Month: selected month
        return dt.year == now.year && dt.month == now.month;
      case 3: // Year: selected year
      default:
        return dt.year == now.year;
    }
  }

  List<Map<String, dynamic>> _computeTopCategories() {
    final isIncome = _type.toLowerCase() == 'income';
    final categoryTotals = <String, double>{};
    final categoryCounts = <String, int>{};
    final categoryIcons = <String, int>{};

    for (final r in _activeRows) {
      final type = (r['type'] as String).toLowerCase().trim();
      if ((isIncome && type != 'income') || (!isIncome && type != 'expense')) {
        continue;
      }

      final dt = DateTime.tryParse(r['date'] as String);
      if (dt == null || !_isDateInCurrentPeriod(dt)) {
        continue;
      }

      final cat = (r['category'] as String?)?.trim() ?? 'Other';
      final amt = (r['amount'] as num).toDouble();
      final icon = r['icon'] as int?;

      categoryTotals[cat] = (categoryTotals[cat] ?? 0) + amt;
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;

      if (icon != null && !categoryIcons.containsKey(cat)) {
        categoryIcons[cat] = icon;
      }
    }

    final sorted = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Show ALL categories that have an amount > 0 in the period
    return sorted
        .where((e) => e.value > 0)
        .map(
          (e) => {
            'category': e.key,
            'amount': e.value,
            'count': categoryCounts[e.key] ?? 1,
            'icon': categoryIcons[e.key],
          },
        )
        .toList();
  }

  // Compute insights
  Map<String, dynamic> _computeInsights() {
    final points = _cachedPoints;
    if (points.isEmpty || !points.any((p) => p > 0)) {
      return {'avgDaily': 0.0, 'highestDay': '-', 'highestAmount': 0.0, 'txnCount': 0};
    }

    final nonZero = points.where((p) => p > 0).toList();
    final avgDaily = nonZero.isEmpty ? 0.0 : nonZero.reduce((a, b) => a + b) / nonZero.length;
    final maxIdx = points.indexOf(points.reduce(math.max));
    final labels = _cachedLabels;
    final highestDay = maxIdx < labels.length ? labels[maxIdx] : '-';
    final highestAmount = points.reduce(math.max);

    // Count transactions in current period
    int txnCount = 0;
    final isIncome = _type.toLowerCase() == 'income';
    for (final r in _activeRows) {
      final type = (r['type'] as String).toLowerCase().trim();
      if ((isIncome && type != 'income') || (!isIncome && type != 'expense')) continue;
      final dt = DateTime.tryParse(r['date'] as String);
      if (dt == null || !_isDateInCurrentPeriod(dt)) continue;
      txnCount++;
    }

    return {
      'avgDaily': avgDaily,
      'highestDay': highestDay,
      'highestAmount': highestAmount,
      'txnCount': txnCount,
    };
  }

  String _formatCurrency(double v) =>
      FormatUtils.formatCurrency(v, compact: true);

  String _getDateRangeLabel() {
    final now = _selectedDate;
    switch (_selectedTab) {
      case 0:
        return DateFormat('MMM dd, yyyy').format(now);
      case 1:
        final startOfWeek = now.subtract(Duration(days: (now.weekday - 1) % 7));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return '${DateFormat('MMM dd').format(startOfWeek)} – ${DateFormat('MMM dd').format(endOfWeek)}';
      case 2:
        return DateFormat('MMMM yyyy').format(now);
      default:
        return DateFormat('yyyy').format(now);
    }
  }

  bool get _canNavigateForward {
    final now = DateTime.now();
    switch (_selectedTab) {
      case 0: // Day
        return _selectedDate.year < now.year ||
            _selectedDate.month < now.month ||
            _selectedDate.day < now.day;
      case 1: // Week
        final startOfWeek = _selectedDate.subtract(Duration(days: (_selectedDate.weekday - 1) % 7));
        final startOfNowWeek = now.subtract(Duration(days: (now.weekday - 1) % 7));
        return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day)
            .isBefore(DateTime(startOfNowWeek.year, startOfNowWeek.month, startOfNowWeek.day));
      case 2: // Month
        return _selectedDate.year < now.year || _selectedDate.month < now.month;
      case 3: // Year
        return _selectedDate.year < now.year;
      default:
        return false;
    }
  }

  void _navigateDate(int delta) {
    HapticFeedback.selectionClick();
    final current = _selectedDate;
    DateTime next;
    switch (_selectedTab) {
      case 0: // Day
        next = current.add(Duration(days: delta));
        break;
      case 1: // Week
        next = current.add(Duration(days: 7 * delta));
        break;
      case 2: // Month
        final newMonth = current.month + delta;
        final newYear = current.year + ((newMonth - 1) ~/ 12);
        final adjustedMonth = ((newMonth - 1) % 12) + 1;
        final maxDays = DateTime(newYear, adjustedMonth + 1, 0).day;
        next = DateTime(newYear, adjustedMonth, current.day.clamp(1, maxDays));
        break;
      case 3: // Year
        next = DateTime(current.year + delta, current.month, current.day);
        break;
      default:
        next = current;
    }

    final today = DateTime.now();
    if (next.isAfter(today)) {
      next = today;
    }

    setState(() {
      _selectedDate = next;
    });
    _scheduleComputation();
  }

  Future<void> _downloadCurrentView() async {
    setState(() => _isDownloading = true);

    try {
      final now = _selectedDate;
      List<Map<String, dynamic>> filteredTransactions = [];
      String title = '';
      String subtitle = '';

      switch (_selectedTab) {
        case 0:
          filteredTransactions = _activeRows
              .where((t) {
                final date = DateTime.tryParse(t['date'] as String);
                if (date == null) return false;
                return date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
              })
              .cast<Map<String, dynamic>>()
              .toList();
          title = 'Daily Report';
          subtitle = DateFormat('MMM dd, yyyy').format(now);
          break;

        case 1:
          final startOfWeek = now.subtract(
            Duration(days: (now.weekday - 1) % 7),
          );
          final start = DateTime(
            startOfWeek.year,
            startOfWeek.month,
            startOfWeek.day,
          );
          final end = start.add(const Duration(days: 7));

          filteredTransactions = _activeRows
              .where((t) {
                final date = DateTime.tryParse(t['date'] as String);
                if (date == null) return false;
                return date.isAfter(
                      start.subtract(const Duration(milliseconds: 1)),
                    ) &&
                    date.isBefore(end);
              })
              .cast<Map<String, dynamic>>()
              .toList();
          title = 'Weekly Report';
          subtitle =
              '${DateFormat('MMM dd').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}';
          break;

        case 2:
          filteredTransactions = _activeRows
              .where((t) {
                final date = DateTime.tryParse(t['date'] as String);
                if (date == null) return false;
                return date.year == now.year && date.month == now.month;
              })
              .cast<Map<String, dynamic>>()
              .toList();
          title = 'Monthly Report';
          subtitle = DateFormat('MMMM yyyy').format(now);
          break;

        case 3:
          filteredTransactions = _activeRows
              .where((t) {
                final date = DateTime.tryParse(t['date'] as String);
                if (date == null) return false;
                return date.year == now.year;
              })
              .cast<Map<String, dynamic>>()
              .toList();
          title = 'Yearly Report';
          subtitle = DateFormat('yyyy').format(now);
          break;
      }

      if (filteredTransactions.isEmpty) {
        if (!mounted) return;
        AppSnackbar.showInfo(
          context,
          'No transactions found for this period',
        );
        return;
      }

      final file = await PdfService.generateMultipleTransactionsPdf(
        transactions: filteredTransactions,
        title: title,
        subtitle: subtitle,
      );

      if (!mounted) return;
      _showPdfOptions(file);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        'Error generating PDF: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _showDatePicker() async {
    HapticFeedback.lightImpact();
    switch (_selectedTab) {
      case 0:
        await _showDayPicker();
        break;
      case 1:
        await _showWeekPicker();
        break;
      case 2:
        await _showMonthPicker();
        break;
      case 3:
        await _showYearPicker();
        break;
    }
  }

  Future<void> _showDayPicker() async {
    DateTime tempDate = _selectedDate;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDark = AppColors.isDark(context);
        return Container(
        height: 300,
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text('Cancel', style: TextStyle(color: AppColors.textSecondaryOf(context))),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'Select Day',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context)),
                  ),
                  CupertinoButton(
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () {
                      setState(() => _selectedDate = tempDate);
                      _scheduleComputation();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: isDark ? Brightness.dark : Brightness.light,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: AppColors.textPrimaryOf(context),
                      fontSize: 20,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selectedDate,
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (date) {
                    tempDate = date;
                  },
                ),
              ),
            ),
          ],
        ),
      );
      },
    );
  }

  Future<void> _showWeekPicker() async {
    DateTime tempDate = _selectedDate;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDark = AppColors.isDark(context);
        return Container(
        height: 300,
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text('Cancel', style: TextStyle(color: AppColors.textSecondaryOf(context))),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'Select Week',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context)),
                  ),
                  CupertinoButton(
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () {
                      setState(() => _selectedDate = tempDate);
                      _scheduleComputation();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: isDark ? Brightness.dark : Brightness.light,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: AppColors.textPrimaryOf(context),
                      fontSize: 20,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selectedDate,
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (date) {
                    tempDate = date;
                  },
                ),
              ),
            ),
          ],
        ),
      );
      },
    );
  }

  Future<void> _showMonthPicker() async {
    DateTime tempDate = _selectedDate;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDark = AppColors.isDark(context);
        return Container(
        height: 300,
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text('Cancel', style: TextStyle(color: AppColors.textSecondaryOf(context))),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'Select Month',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context)),
                  ),
                  CupertinoButton(
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () {
                      setState(() => _selectedDate = tempDate);
                      _scheduleComputation();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: isDark ? Brightness.dark : Brightness.light,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      color: AppColors.textPrimaryOf(context),
                      fontSize: 20,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.monthYear,
                  initialDateTime: _selectedDate,
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (date) {
                    tempDate = date;
                  },
                ),
              ),
            ),
          ],
        ),
      );
      },
    );
  }

  Future<void> _showYearPicker() async {
    int selectedYear = _selectedDate.year;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDark = AppColors.isDark(context);
        return Container(
        height: 300,
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text('Cancel', style: TextStyle(color: AppColors.textSecondaryOf(context))),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'Select Year',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context)),
                  ),
                  CupertinoButton(
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () {
                      setState(
                        () => _selectedDate = DateTime(selectedYear, 1, 1),
                      );
                      _scheduleComputation();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: isDark ? Brightness.dark : Brightness.light,
                ),
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: DateTime.now().year - selectedYear,
                  ),
                  itemExtent: 40,
                  onSelectedItemChanged: (index) {
                    selectedYear = DateTime.now().year - index;
                  },
                  children: List.generate(DateTime.now().year - 2020 + 1, (
                    index,
                  ) {
                    final year = DateTime.now().year - index;
                    return Center(
                      child: Text(
                        year.toString(),
                        style: TextStyle(fontSize: 22, color: AppColors.textPrimaryOf(context)),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      );
      },
    );
  }

  void _showPdfOptions(file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.isDark(context) ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'PDF Generated Successfully!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context)),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.open_in_new, color: AppColors.primary),
              ),
              title: Text('Open PDF', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context))),
              onTap: () {
                Navigator.pop(context);
                PdfService.openPdf(file);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.share, color: AppColors.secondary),
              ),
              title: Text('Share PDF', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context))),
              onTap: () {
                Navigator.pop(context);
                PdfService.sharePdf(file);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.income.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.print, color: AppColors.income),
              ),
              title: Text('Print PDF', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context))),
              onTap: () {
                Navigator.pop(context);
                PdfService.printPdf(file);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── BUILD ───

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top;
    final isDark = AppColors.isDark(context);
    final headerColor = isDark
        ? const Color(0xFF0F2624)
        : const Color(0xFF0F3632);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundOf(context),
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: topPadding + 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [Color(0xFF0F2624), Color(0xFF1E5D57)]
                        : const [Color(0xFF0F3632), Color(0xFF2C7A72)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
                ),
              ),
            ),
            const Center(
              child: BuddyLoadingIndicator(size: 56),
            ),
          ],
        ),
      );
    }

    final points = _cachedPoints;
    final labels = _cachedLabels;
    final total = _cachedTotal;
    final topCategories = _cachedTopCategories;
    final hasData = points.any((p) => p > 0);
    final insights = _computeInsights();
    final avgDaily = insights['avgDaily'] as double;
    final highestAmount = insights['highestAmount'] as double;
    final highestDay = insights['highestDay'] as String;
    final txnCount = insights['txnCount'] as int;
    final periodUnit = _selectedTab == 0 ? 'hr' : (_selectedTab == 1 ? 'day' : (_selectedTab == 2 ? 'day' : 'mo'));

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: Stack(
        children: [
          // Dynamic overscroll backdrop matching hero header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _scrollController,
              builder: (context, _) {
                final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                final overscroll = offset < 0 ? -offset : 0.0;
                if (overscroll <= 0) return const SizedBox.shrink();
                return Container(
                  height: topPadding + overscroll + 40,
                  color: headerColor,
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
              BuddyRefreshControl(
                onRefresh: refreshData,
                backgroundColor: headerColor,
                topPadding: topPadding,
              ),
              SliverToBoxAdapter(
                child: _buildHeroHeader(
                  isDark: isDark,
                  topPadding: topPadding,
                  total: total,
                  txnCount: txnCount,
                  avgDaily: avgDaily,
                  highestAmount: highestAmount,
                  periodUnit: periodUnit,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  mq.padding.bottom + 110,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildChartCard(
                      points: points,
                      labels: labels,
                      hasData: hasData,
                      total: total,
                      topCategories: topCategories,
                      isDark: isDark,
                    ),
                    if (hasData) ...[
                      const SizedBox(height: 20),
                      _buildInsightsRow(
                        avgDaily: avgDaily,
                        highestDay: highestDay,
                        highestAmount: highestAmount,
                        txnCount: txnCount,
                        periodLabel: _selectedTab == 0 ? 'Hourly' : (_selectedTab == 1 ? 'Daily' : (_selectedTab == 2 ? 'Daily' : 'Monthly')),
                      ),
                    ],
                    if (topCategories.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildTopCategories(topCategories, total),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── HERO HEADER (MATCHING HOME & PROFILE) ───

  Widget _buildHeroHeader({
    required bool isDark,
    required double topPadding,
    required double total,
    required int txnCount,
    required double avgDaily,
    required double highestAmount,
    required String periodUnit,
  }) {
    final isExpense = _type == 'Expense';
    final accentColor = isExpense ? AppColors.expense : AppColors.income;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF0F2624), Color(0xFF1E5D57)]
              : const [Color(0xFF0F3632), Color(0xFF2C7A72)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, topPadding + 10, 20, 20),
      child: Column(
        children: [
          // ── 1. Top Bar: Title + Date Navigator + PDF Export ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Statistics',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              // Export PDF button
              GestureDetector(
                onTap: _isDownloading ? null : _downloadCurrentView,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDownloading)
                        const BuddyLoadingIndicator(size: 14)
                      else ...[
                        const Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'PDF',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── 2. Date Range Navigator with < Date Label > ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => _navigateDate(-1),
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  splashRadius: 16,
                ),
                GestureDetector(
                  onTap: _showDatePicker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: Colors.white70, size: 13),
                      const SizedBox(width: 7),
                      Text(
                        _getDateRangeLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _canNavigateForward ? () => _navigateDate(1) : null,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: _canNavigateForward ? Colors.white : Colors.white30,
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  splashRadius: 16,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── 3. Frosted Hero Total Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.15),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isExpense ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                            color: isExpense ? const Color(0xFFFF8A80) : const Color(0xFF80CBC4),
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Total $_type',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _tabs[_selectedTab],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  FormatUtils.formatCurrencyFull(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildHeroChip(Icons.receipt_long_rounded, '$txnCount ${txnCount == 1 ? "Txn" : "Txns"}'),
                    if (avgDaily > 0)
                      _buildHeroChip(Icons.analytics_outlined, 'Avg ${_formatCurrency(avgDaily)}/$periodUnit'),
                    if (highestAmount > 0)
                      _buildHeroChip(Icons.bolt_rounded, 'Peak ${_formatCurrency(highestAmount)}'),
                    _buildHeroChip(
                      _includeDebtsInHome ? Icons.handshake_rounded : Icons.filter_alt_off_rounded,
                      _includeDebtsInHome ? 'Debts on Home' : 'Debts Excluded',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── 4. Type & Period Controls (Cohesive Frosted Glass) ──
          _buildHeroTypeToggle(),
          const SizedBox(height: 10),
          _buildHeroPeriodTabs(),
        ],
      ),
    );
  }

  Widget _buildHeroChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTypeToggle() {
    final isExpense = _type == 'Expense';
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 2) / 2;
          final animatedLeft = _typePage.clamp(0.0, 1.0) * itemWidth;

          final activeColor = isExpense ? const Color(0xFFE57373) : const Color(0xFF4DB6AC);

          return GestureDetector(
            onHorizontalDragStart: (details) {
              setState(() {
                _typeDragging = true;
                _typeDragStartPage = _typePage;
                _typeDragStartX = details.globalPosition.dx;
              });
            },
            onHorizontalDragUpdate: (details) {
              final deltaX = details.globalPosition.dx - _typeDragStartX;
              final deltaPages = deltaX / itemWidth;
              setState(() {
                _typePage = (_typeDragStartPage + deltaPages).clamp(0.0, 1.0);
              });
            },
            onHorizontalDragEnd: (details) {
              final target = _typePage.round();
              HapticFeedback.selectionClick();
              setState(() {
                _typeDragging = false;
                _typePage = target.toDouble();
                _type = target == 0 ? 'Expense' : 'Income';
              });
              _scheduleComputation();
            },
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: _typeDragging ? Duration.zero : const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: animatedLeft,
                  top: 0,
                  bottom: 0,
                  width: itemWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: LinearGradient(
                        colors: [
                          activeColor,
                          activeColor.withValues(alpha: 0.85),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
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
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _type = 'Expense';
                            _typePage = 0;
                          });
                          _scheduleComputation();
                        },
                        child: Container(
                          color: Colors.transparent,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.trending_down_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Expense',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: _typePage < 0.5 ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _type = 'Income';
                            _typePage = 1;
                          });
                          _scheduleComputation();
                        },
                        child: Container(
                          color: Colors.transparent,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.trending_up_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Income',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: _typePage >= 0.5 ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroPeriodTabs() {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final itemWidth = totalWidth / _tabs.length;
          final animatedLeft = _tabPage.clamp(0.0, _tabs.length - 1.0) * itemWidth;

          return GestureDetector(
            onHorizontalDragStart: (details) {
              setState(() {
                _tabDragging = true;
                _tabDragStartPage = _tabPage;
                _tabDragStartX = details.globalPosition.dx;
              });
            },
            onHorizontalDragUpdate: (details) {
              final deltaX = details.globalPosition.dx - _tabDragStartX;
              final deltaPages = deltaX / itemWidth;
              setState(() {
                _tabPage = (_tabDragStartPage + deltaPages).clamp(0.0, _tabs.length - 1.0);
              });
            },
            onHorizontalDragEnd: (details) {
              final target = _tabPage.round();
              HapticFeedback.selectionClick();
              setState(() {
                _tabDragging = false;
                _tabPage = target.toDouble();
                _selectedTab = target;
                _selectedDate = DateTime.now();
              });
              _scheduleComputation();
            },
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: _tabDragging ? Duration.zero : const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: animatedLeft,
                  top: 0,
                  bottom: 0,
                  width: itemWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.25),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: List.generate(_tabs.length, (i) {
                    final distance = (_tabPage - i).abs();
                    final selected = distance < 0.5;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedTab = i;
                            _tabPage = i.toDouble();
                            _selectedDate = DateTime.now();
                          });
                          _scheduleComputation();
                        },
                        child: Container(
                          color: Colors.transparent,
                          child: Center(
                            child: Text(
                              _tabs[i],
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.white70,
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                fontSize: 12.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── CHART CARD (SMOOTH SPLINE CURVE / MODERN BARS / DONUT) ───

  Widget _buildChartCard({
    required List<double> points,
    required List<String> labels,
    required bool hasData,
    required double total,
    required List<Map<String, dynamic>> topCategories,
    required bool isDark,
  }) {
    final chartThemeColor = _type == 'Expense' ? AppColors.expense : AppColors.income;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header with Title and Mode Switcher
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: chartThemeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _chartViewMode == 2
                        ? 'Category Breakdown'
                        : (_type == 'Expense' ? 'Spending Trend' : 'Earnings Trend'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceOf(context),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildChartModeBtn(0, Icons.show_chart_rounded, 'Curve'),
                      const SizedBox(width: 2),
                      _buildChartModeBtn(1, Icons.bar_chart_rounded, 'Bars'),
                      const SizedBox(width: 2),
                      _buildChartModeBtn(2, Icons.pie_chart_outline_rounded, 'Donut'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 0.6),

          // Dynamic Scrubber Readout for Line and Bar charts
          if (hasData && _chartViewMode != 2)
            _buildLiveScrubberHeader(
              points: points,
              labels: labels,
              total: total,
              themeColor: chartThemeColor,
              isDark: isDark,
            ),

          // Chart Body
          if (!hasData)
            _buildEmptyChartState(isDark)
          else if (_chartViewMode == 2)
            _buildDonutChart(topCategories, total, isDark)
          else if (_chartViewMode == 1)
            _buildBarChart(points, labels, chartThemeColor, isDark)
          else
            _buildLineAreaChart(points, labels, chartThemeColor, isDark),
        ],
      ),
    );
  }

  Widget _buildChartModeBtn(int mode, IconData icon, String label) {
    final isSelected = _chartViewMode == mode;
    final isDark = AppColors.isDark(context);
    final accentColor = _type == 'Expense' ? AppColors.expense : AppColors.income;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _chartViewMode = mode;
          _touchedPieIndex = -1;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? accentColor.withValues(alpha: 0.25) : accentColor.withValues(alpha: 0.15))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: isSelected
              ? Border.all(color: accentColor.withValues(alpha: 0.5), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? accentColor
                  : AppColors.textSecondaryOf(context),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? accentColor
                    : AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChartState(bool isDark) {
    return Container(
      height: 220,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_graph_rounded,
              size: 36,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No ${_type.toLowerCase()}s in this period',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use the ‹ › arrows above to check other dates',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Live Scrubber Header (Dynamic Robinhood/Revolut-style readout) ──

  Widget _buildLiveScrubberHeader({
    required List<double> points,
    required List<String> labels,
    required double total,
    required Color themeColor,
    required bool isDark,
  }) {
    final hasTouch = _touchedChartIndex != null &&
        _touchedChartIndex! >= 0 &&
        _touchedChartIndex! < points.length;

    final double displayAmount = hasTouch ? points[_touchedChartIndex!] : total;
    final String displayLabel = hasTouch
        ? '${labels[_touchedChartIndex!]} • ${_selectedTab == 0 ? "Hour" : (_selectedTab == 1 ? "Day" : (_selectedTab == 2 ? "Date" : "Month"))}'
        : (_type == 'Expense' ? 'Total Period Expense' : 'Total Period Income');

    final double pctOfTotal = (total > 0 && hasTouch)
        ? (displayAmount / total * 100)
        : 100.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasTouch
            ? themeColor.withValues(alpha: isDark ? 0.16 : 0.08)
            : AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasTouch
              ? themeColor.withValues(alpha: 0.4)
              : AppColors.borderOf(context).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: hasTouch
                  ? themeColor.withValues(alpha: 0.22)
                  : themeColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasTouch ? Icons.touch_app_rounded : Icons.insights_rounded,
              size: 14,
              color: themeColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  FormatUtils.formatCurrencyFull(displayAmount),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: hasTouch ? themeColor : AppColors.textPrimaryOf(context),
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          if (hasTouch && total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${pctOfTotal.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: themeColor,
                ),
              ),
            )
          else
            Text(
              'Touch graph to inspect',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondaryOf(context),
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  // ── Mode 0: Smooth Spline Curve Area Chart ──

  Widget _buildLineAreaChart(
    List<double> points,
    List<String> labels,
    Color lineBarColor,
    bool isDark,
  ) {
    double maxVal = points.isNotEmpty ? points.reduce((a, b) => a > b ? a : b) : 0.0;
    double roundedMax = _computeNiceMax(maxVal);
    if (roundedMax == 0) roundedMax = 100;
    double interval = roundedMax / 4;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 18, 14),
      child: SizedBox(
        height: 250,
        child: RepaintBoundary(
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchSpotThreshold: 24,
                touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                  if (!event.isInterestedForInteractions ||
                      touchResponse == null ||
                      touchResponse.lineBarSpots == null ||
                      touchResponse.lineBarSpots!.isEmpty) {
                    if (_touchedChartIndex != null) {
                      setState(() => _touchedChartIndex = null);
                    }
                    return;
                  }
                  final spot = touchResponse.lineBarSpots!.first;
                  if (_touchedChartIndex != spot.spotIndex) {
                    HapticFeedback.selectionClick();
                    setState(() => _touchedChartIndex = spot.spotIndex);
                  }
                },
                getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                  return spotIndexes.map((spotIndex) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: lineBarColor.withValues(alpha: 0.8),
                        strokeWidth: 1.5,
                        dashArray: [4, 4],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          return FlDotCirclePainter(
                            radius: 6.5,
                            color: Colors.white,
                            strokeWidth: 3,
                            strokeColor: lineBarColor,
                          );
                        },
                      ),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (spot) => isDark ? const Color(0xFF1E293B) : const Color(0xFF2C3E50),
                  tooltipRoundedRadius: 12,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final idx = spot.spotIndex;
                      final label = idx < labels.length ? labels[idx] : '';
                      return LineTooltipItem(
                        '$label\n',
                        TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(
                            text: '₹${_formatCompactCurrency(spot.y)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: AppColors.borderOf(context).withValues(alpha: 0.35),
                    strokeWidth: 1,
                    dashArray: [6, 4],
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '₹${_formatCompactCurrency(value)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondaryOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();

                      bool shouldShow = false;
                      if (_selectedTab == 0) {
                        shouldShow = idx % 4 == 0;
                      } else if (_selectedTab == 1) {
                        shouldShow = true;
                      } else if (_selectedTab == 2) {
                        shouldShow = idx == 0 || idx % 5 == 0 || idx == labels.length - 1;
                      } else {
                        shouldShow = idx % 2 == 0;
                      }

                      if (!shouldShow) return const SizedBox.shrink();

                      final isSelected = _touchedChartIndex == idx;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          labels[idx],
                          style: TextStyle(
                            fontSize: _selectedTab == 1 ? 10 : 9,
                            color: isSelected ? lineBarColor : AppColors.textSecondaryOf(context),
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (points.length - 1).toDouble().clamp(0.0, double.infinity),
              minY: 0,
              maxY: roundedMax,
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(
                    points.length,
                    (i) => FlSpot(i.toDouble(), points[i]),
                  ),
                  isCurved: true,
                  curveSmoothness: 0.35,
                  preventCurveOverShooting: true,
                  color: lineBarColor,
                  barWidth: 3.2,
                  isStrokeCapRound: true,
                  shadow: Shadow(
                    color: lineBarColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                  dotData: FlDotData(
                    show: points.length <= 12,
                    getDotPainter: (spot, percent, barData, index) {
                      final isSelected = _touchedChartIndex == index;
                      return FlDotCirclePainter(
                        radius: isSelected ? 5.5 : 3.5,
                        color: Colors.white,
                        strokeWidth: isSelected ? 3.0 : 2.2,
                        strokeColor: lineBarColor,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        lineBarColor.withValues(alpha: isDark ? 0.38 : 0.25),
                        lineBarColor.withValues(alpha: isDark ? 0.12 : 0.08),
                        lineBarColor.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          ),
        ),
      ),
    );
  }

  // ── Mode 1: Modern Rounded Bar Chart ──

  Widget _buildBarChart(
    List<double> points,
    List<String> labels,
    Color barColor,
    bool isDark,
  ) {
    double maxVal = points.isNotEmpty ? points.reduce((a, b) => a > b ? a : b) : 0.0;
    double roundedMax = _computeNiceMax(maxVal);
    if (roundedMax == 0) roundedMax = 100;
    double interval = roundedMax / 4;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 18, 14),
      child: SizedBox(
        height: 250,
        child: RepaintBoundary(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: roundedMax,
              minY: 0,
              groupsSpace: _selectedTab == 2 ? 3 : 6,
              barTouchData: BarTouchData(
                enabled: true,
                touchCallback: (FlTouchEvent event, BarTouchResponse? touchResponse) {
                  if (!event.isInterestedForInteractions || touchResponse == null || touchResponse.spot == null) {
                    if (_touchedChartIndex != null) {
                      setState(() => _touchedChartIndex = null);
                    }
                    return;
                  }
                  final spot = touchResponse.spot!;
                  if (_touchedChartIndex != spot.touchedBarGroupIndex) {
                    HapticFeedback.selectionClick();
                    setState(() => _touchedChartIndex = spot.touchedBarGroupIndex);
                  }
                },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => isDark ? const Color(0xFF1E293B) : const Color(0xFF2C3E50),
                  tooltipRoundedRadius: 10,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final label = groupIndex < labels.length ? labels[groupIndex] : '';
                    return BarTooltipItem(
                      '$label\n',
                      TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: '₹${_formatCompactCurrency(rod.toY)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '₹${_formatCompactCurrency(value)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondaryOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();

                      bool shouldShow = false;
                      if (_selectedTab == 0) {
                        shouldShow = idx % 4 == 0;
                      } else if (_selectedTab == 1) {
                        shouldShow = true;
                      } else if (_selectedTab == 2) {
                        shouldShow = idx == 0 || idx % 5 == 0 || idx == labels.length - 1;
                      } else {
                        shouldShow = idx % 2 == 0;
                      }

                      if (!shouldShow) return const SizedBox.shrink();

                      final isSelected = _touchedChartIndex == idx;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          labels[idx],
                          style: TextStyle(
                            fontSize: _selectedTab == 1 ? 10 : 9,
                            color: isSelected ? barColor : AppColors.textSecondaryOf(context),
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: AppColors.borderOf(context).withValues(alpha: 0.35),
                    strokeWidth: 1,
                    dashArray: [6, 4],
                  );
                },
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(
                points.length,
                (index) {
                  final isSelected = _touchedChartIndex == index;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: points[index],
                        gradient: LinearGradient(
                          colors: [
                            barColor,
                            barColor.withValues(alpha: isSelected ? 0.95 : 0.65),
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: _selectedTab == 2 ? 5.5 : (_selectedTab == 0 ? 8 : 14),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: roundedMax,
                          color: barColor.withValues(alpha: 0.04),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            swapAnimationDuration: const Duration(milliseconds: 300),
            swapAnimationCurve: Curves.easeOutCubic,
          ),
        ),
      ),
    );
  }

  // ── Mode 2: Interactive Category Donut / Ring Breakdown ──

  Widget _buildDonutChart(
    List<Map<String, dynamic>> categories,
    double total,
    bool isDark,
  ) {
    if (categories.isEmpty || total <= 0) {
      return _buildEmptyChartState(isDark);
    }

    // Requirement 4: "it should show all the categories availlable that has some amount."
    final displayCategories = categories.where((c) => (c['amount'] as double) > 0).toList();

    String centerTitle = 'Total $_type';
    String centerValue = FormatUtils.formatCurrency(total, compact: true);
    String centerSub = 'Tap slice or category';
    Color centerColor = isDark ? Colors.white : AppColors.textPrimaryOf(context);

    if (_touchedPieIndex >= 0 && _touchedPieIndex < displayCategories.length) {
      final cat = displayCategories[_touchedPieIndex];
      final amt = cat['amount'] as double;
      final pct = total > 0 ? (amt / total * 100) : 0.0;
      centerTitle = cat['category'] as String;
      centerValue = FormatUtils.formatCurrency(amt, compact: true);
      centerSub = '${pct.toStringAsFixed(1)}%';
      centerColor = AppColors.getCategoryColor(cat['category'] as String);
    }

    return Column(
      children: [
        SizedBox(
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          _touchedPieIndex = -1;
                          return;
                        }
                        _touchedPieIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 3,
                  centerSpaceRadius: 54,
                  sections: List.generate(displayCategories.length, (i) {
                    final isTouched = i == _touchedPieIndex;
                    final cat = displayCategories[i];
                    final amt = cat['amount'] as double;
                    final pct = total > 0 ? (amt / total * 100) : 0.0;
                    final color = AppColors.getCategoryColor(cat['category'] as String);
                    final radius = isTouched ? 36.0 : 28.0;

                    return PieChartSectionData(
                      color: color,
                      value: amt,
                      title: pct >= 6 ? '${pct.toStringAsFixed(0)}%' : '',
                      radius: radius,
                      titleStyle: TextStyle(
                        fontSize: isTouched ? 13 : 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: const [Shadow(color: Colors.black45, blurRadius: 3)],
                      ),
                    );
                  }),
                ),
                swapAnimationDuration: const Duration(milliseconds: 300),
                swapAnimationCurve: Curves.easeOutCubic,
              ),
              IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerTitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      centerValue,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: centerColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      centerSub,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: displayCategories.asMap().entries.map((entry) {
              final idx = entry.key;
              final cat = entry.value;
              final isTouched = idx == _touchedPieIndex;
              final color = AppColors.getCategoryColor(cat['category'] as String);
              final pct = total > 0 ? ((cat['amount'] as double) / total * 100) : 0.0;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _touchedPieIndex = (_touchedPieIndex == idx) ? -1 : idx;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: isTouched
                        ? color.withValues(alpha: 0.18)
                        : AppColors.surfaceOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isTouched ? color : AppColors.borderOf(context).withValues(alpha: 0.35),
                      width: isTouched ? 1.5 : 1,
                    ),
                    boxShadow: isTouched
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cat['category'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isTouched ? FontWeight.w800 : FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  double _computeNiceMax(double val) {
    if (val <= 0) return 100;
    double factor = 1.0;
    while (val > 100) {
      val /= 10;
      factor *= 10;
    }
    while (val < 10 && factor > 1) {
      val *= 10;
      factor /= 10;
    }
    double rounded;
    if (val <= 10) {
      rounded = 10;
    } else if (val <= 20) {
      rounded = 20;
    } else if (val <= 25) {
      rounded = 25;
    } else if (val <= 50) {
      rounded = 50;
    } else if (val <= 75) {
      rounded = 75;
    } else {
      rounded = 100;
    }
    return rounded * factor;
  }

  String _formatCompactCurrency(double value) {
    if (value >= 10000000) {
      return '${(value / 10000000).toStringAsFixed(1)}Cr';
    } else if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }

  // ─── INSIGHTS ROW ───

  Widget _buildInsightsRow({
    required double avgDaily,
    required String highestDay,
    required double highestAmount,
    required int txnCount,
    required String periodLabel,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildInsightCard(
            icon: Icons.analytics_outlined,
            label: 'Avg $periodLabel',
            value: _formatCurrency(avgDaily),
            color: const Color(0xFF5C6BC0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildInsightCard(
            icon: Icons.bolt_rounded,
            label: 'Peak ($highestDay)',
            value: _formatCurrency(highestAmount),
            color: const Color(0xFFFF7043),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildInsightCard(
            icon: Icons.receipt_long_rounded,
            label: 'Transactions',
            value: '$txnCount',
            color: const Color(0xFF26A69A),
          ),
        ),
      ],
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ─── CATEGORY BREAKDOWN LIST (ALL CATEGORIES WITH AMOUNT) ───

  Widget _buildTopCategories(
    List<Map<String, dynamic>> topCategories,
    double total,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_type == 'Expense' ? 'Expense' : 'Income'} Categories',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimaryOf(context),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.borderOf(context).withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '${topCategories.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Tap to view',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondaryOf(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Category Cards (Showing ALL categories that have an amount > 0)
        ...topCategories.asMap().entries.map((entry) {
          final idx = entry.key;
          final cat = entry.value;
          final percentage = total > 0
              ? (cat['amount'] as double) / total * 100
              : 0.0;
          final catColor = AppColors.getCategoryColor(cat['category'] as String);
          final txnCount = (cat['count'] as int?) ?? 1;

          return GestureDetector(
            onTap: () => _showCategoryTransactionsSheet(cat['category'] as String, catColor),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.borderOf(context).withValues(alpha: 0.5),
                ),
                boxShadow: AppColors.cardShadowOf(context),
              ),
              child: Row(
                children: [
                  // Rank Badge
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: idx == 0
                          ? const Color(0xFFFFD54F).withValues(alpha: 0.25)
                          : idx == 1
                              ? const Color(0xFFCFD8DC).withValues(alpha: 0.35)
                              : idx == 2
                                  ? const Color(0xFFFFCC80).withValues(alpha: 0.25)
                                  : AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: idx == 0
                            ? const Color(0xFFFFD54F)
                            : idx == 1
                                ? const Color(0xFFB0BEC5)
                                : idx == 2
                                    ? const Color(0xFFFFCC80)
                                    : AppColors.borderOf(context).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        idx == 0
                            ? '🥇'
                            : idx == 1
                                ? '🥈'
                                : idx == 2
                                    ? '🥉'
                                    : '#${idx + 1}',
                        style: TextStyle(
                          fontSize: idx < 3 ? 12 : 10,
                          fontWeight: FontWeight.w800,
                          color: idx < 3
                              ? null
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Category Icon
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      IconHelper.getIcon(cat['icon']),
                      color: catColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name + Progress Bar + Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cat['category'] as String,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimaryOf(context),
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '$txnCount ${txnCount == 1 ? "txn" : "txns"}',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryOf(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: AppColors.surfaceOf(context),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (percentage / 100).clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                gradient: LinearGradient(
                                  colors: [
                                    catColor,
                                    catColor.withValues(alpha: 0.65),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Amount + Percentage
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(cat['amount'] as double),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _type == 'Income'
                              ? AppColors.income
                              : AppColors.textPrimaryOf(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: catColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ─── CATEGORY TRANSACTIONS BOTTOM SHEET ───

  void _showCategoryTransactionsSheet(String categoryName, Color catColor) {
    HapticFeedback.lightImpact();
    final isIncome = _type.toLowerCase() == 'income';

    final txns = _activeRows.where((r) {
      final type = (r['type'] as String).toLowerCase().trim();
      if ((isIncome && type != 'income') || (!isIncome && type != 'expense')) {
        return false;
      }
      final cat = (r['category'] as String?)?.trim() ?? 'Other';
      if (cat != categoryName) return false;
      final dt = DateTime.tryParse(r['date'] as String);
      return dt != null && _isDateInCurrentPeriod(dt);
    }).toList();

    double totalAmt = txns.fold<double>(0.0, (sum, r) => sum + (r['amount'] as num).toDouble());

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardOf(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(ctx).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        IconHelper.getIcon(txns.isNotEmpty ? txns.first['icon'] : null),
                        color: catColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            categoryName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimaryOf(ctx),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${txns.length} ${txns.length == 1 ? "transaction" : "transactions"} • ${_getDateRangeLabel()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryOf(ctx),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      FormatUtils.formatCurrencyFull(totalAmt),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _type == 'Income' ? AppColors.income : AppColors.textPrimaryOf(ctx),
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.6),
              Flexible(
                child: txns.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No transactions found for this category.',
                          style: TextStyle(color: AppColors.textSecondaryOf(ctx)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: txns.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = txns[i];
                          final dt = DateTime.tryParse(item['date'] as String);
                          final dateStr = dt != null ? DateFormat('MMM dd, hh:mm a').format(dt) : '';
                          final note = (item['note'] as String?)?.trim();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.borderOf(context).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        note != null && note.isNotEmpty ? note : categoryName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: AppColors.textPrimaryOf(context),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        dateStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondaryOf(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  FormatUtils.formatCurrencyFull((item['amount'] as num).toDouble()),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: _type == 'Income' ? AppColors.income : AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
