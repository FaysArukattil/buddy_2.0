import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
// ignore: depend_on_referenced_packages
import 'package:fl_chart/fl_chart.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/pdf_service.dart';
import 'package:intl/intl.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => StatisticsScreenState();
}

class StatisticsScreenState extends State<StatisticsScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  int _selectedTab = 0;
  String _type = 'Expense';
  final List<String> _tabs = const ['Day', 'Week', 'Month', 'Year'];
  bool _isDownloading = false;
  DateTime _selectedDate = DateTime.now();

  // Swipe gesture tracking
  double _tabPage = 0;
  bool _tabDragging = false;
  double _tabDragStartPage = 0;
  double _tabDragStartX = 0;

  double _typePage = 0;
  bool _typeDragging = false;
  double _typeDragStartPage = 0;
  double _typeDragStartX = 0;

  final FirestoreService _firestore = FirestoreService.instance;
  List<Map<String, dynamic>> _rows = [];

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
    _load();
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    debugPrint('📊 STATISTICS: Loading transactions...');
    try {
      final txns = await _firestore.getAllTransactions();
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
    await _load();
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
    return '$_selectedTab-$_type-${_selectedDate.toString()}-${_rows.length}';
  }

  List<double> _computePoints() {
    final isIncome = _type.toLowerCase() == 'income';
    final now = _selectedDate;

    switch (_selectedTab) {
      case 0: // Day: 24 hours
        final buckets = List<double>.filled(24, 0);
        for (final r in _rows) {
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

        for (final r in _rows) {
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
        for (final r in _rows) {
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
        for (final r in _rows) {
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

  List<Map<String, dynamic>> _computeTopCategories() {
    final isIncome = _type.toLowerCase() == 'income';
    final categoryTotals = <String, double>{};
    final categoryIcons = <String, int>{};

    for (final r in _rows) {
      final type = (r['type'] as String).toLowerCase().trim();
      if ((isIncome && type != 'income') || (!isIncome && type != 'expense')) {
        continue;
      }

      final cat = r['category'] as String;
      final amt = (r['amount'] as num).toDouble();
      final icon = r['icon'] as int?;

      categoryTotals[cat] = (categoryTotals[cat] ?? 0) + amt;

      if (icon != null && !categoryIcons.containsKey(cat)) {
        categoryIcons[cat] = icon;
      }
    }

    final sorted = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .take(5)
        .map(
          (e) => {
            'category': e.key,
            'amount': e.value,
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
    for (final r in _rows) {
      final type = (r['type'] as String).toLowerCase().trim();
      if ((isIncome && type != 'income') || (!isIncome && type != 'expense')) continue;
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

  Future<void> _downloadCurrentView() async {
    setState(() => _isDownloading = true);

    try {
      final now = _selectedDate;
      List<Map<String, dynamic>> filteredTransactions = [];
      String title = '';
      String subtitle = '';

      switch (_selectedTab) {
        case 0:
          filteredTransactions = _rows
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

          filteredTransactions = _rows
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
          filteredTransactions = _rows
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
          filteredTransactions = _rows
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No transactions found for this period'),
            backgroundColor: AppColors.primary,
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating PDF: $e'),
          backgroundColor: Colors.red,
        ),
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
      builder: (context) => Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Select Day',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _selectedDate,
                maximumDate: DateTime.now(),
                onDateTimeChanged: (date) {
                  tempDate = date;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWeekPicker() async {
    DateTime tempDate = _selectedDate;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Select Week',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _selectedDate,
                maximumDate: DateTime.now(),
                onDateTimeChanged: (date) {
                  tempDate = date;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMonthPicker() async {
    DateTime tempDate = _selectedDate;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Select Month',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.monthYear,
                initialDateTime: _selectedDate,
                maximumDate: DateTime.now(),
                onDateTimeChanged: (date) {
                  tempDate = date;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showYearPicker() async {
    int selectedYear = _selectedDate.year;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Select Year',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
                      style: const TextStyle(fontSize: 22),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPdfOptions(file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'PDF Generated Successfully!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
              title: const Text('Open PDF', style: TextStyle(fontWeight: FontWeight.w600)),
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
              title: const Text('Share PDF', style: TextStyle(fontWeight: FontWeight.w600)),
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
              title: const Text('Print PDF', style: TextStyle(fontWeight: FontWeight.w600)),
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundOf(context),
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    strokeWidth: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final points = _cachedPoints;
    final labels = _cachedLabels;
    final total = _cachedTotal;
    final topCategories = _cachedTopCategories;
    final hasData = points.any((p) => p > 0);

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildPeriodTabs(),
                    const SizedBox(height: 16),
                    _buildTypeToggle(),
                    const SizedBox(height: 16),
                    _buildTotalCard(total),
                    const SizedBox(height: 20),
                    _buildChartCard(points, labels, hasData),
                    if (hasData) ...[
                      const SizedBox(height: 20),
                      _buildInsightsRow(),
                    ],
                    if (topCategories.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildTopCategories(topCategories, total),
                    ],
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── APP BAR ───

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Calendar button
          GestureDetector(
            onTap: _showDatePicker,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.borderOf(context).withValues(alpha: 0.5),
                ),
                boxShadow: AppColors.cardShadowOf(context),
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                color: AppColors.textPrimaryOf(context),
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Title
          Expanded(
            child: Column(
              children: [
                Text(
                  'Statistics',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: _showDatePicker,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getDateRangeLabel(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Download button
          GestureDetector(
            onTap: _isDownloading ? null : _downloadCurrentView,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _isDownloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(
                      Icons.download_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PERIOD TABS ───

  Widget _buildPeriodTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          setState(() {
            _tabDragging = true;
            _tabDragStartPage = _tabPage;
            _tabDragStartX = details.globalPosition.dx;
          });
        },
        onHorizontalDragUpdate: (details) {
          final screenWidth = MediaQuery.of(context).size.width - 40;
          final itemWidth = screenWidth / _tabs.length;
          final deltaX = details.globalPosition.dx - _tabDragStartX;
          final deltaPages = deltaX / itemWidth;
          setState(() {
            _tabPage = (_tabDragStartPage + deltaPages).clamp(
              0.0,
              _tabs.length - 1.0,
            );
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
        child: Container(
          height: 50,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.borderOf(context).withValues(alpha: 0.5),
            ),
            boxShadow: AppColors.cardShadowOf(context),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              const itemCount = 4;
              final itemWidth = totalWidth / itemCount;
              final indicatorWidth = itemWidth - 6;
              final animatedLeft =
                  (_tabPage.clamp(0, itemCount - 1) * itemWidth) + 3;

              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: _tabDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: animatedLeft,
                    top: 0,
                    bottom: 0,
                    width: indicatorWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.secondary,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
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
                                  color: selected
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  fontSize: 13,
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
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── TYPE TOGGLE ───

  Widget _buildTypeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Container(
        height: 50,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.borderOf(context).withValues(alpha: 0.5),
          ),
          boxShadow: AppColors.cardShadowOf(context),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            const itemCount = 2;
            final itemWidth = totalWidth / itemCount;
            final indicatorWidth = itemWidth - 6;
            final animatedLeft =
                (_typePage.clamp(0, itemCount - 1) * itemWidth) + 3;

            final isExpense = _typePage < 0.5;
            final activeColor = isExpense ? AppColors.expense : AppColors.income;

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
                    duration: _typeDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: animatedLeft,
                    top: 0,
                    bottom: 0,
                    width: indicatorWidth,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            activeColor,
                            activeColor.withValues(alpha: 0.8),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.3),
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
                        child: _buildTypeOption(
                          icon: Icons.trending_down_rounded,
                          text: 'Expense',
                          selected: _typePage < 0.5,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _type = 'Expense';
                              _typePage = 0;
                            });
                            _scheduleComputation();
                          },
                        ),
                      ),
                      Expanded(
                        child: _buildTypeOption(
                          icon: Icons.trending_up_rounded,
                          text: 'Income',
                          selected: _typePage >= 0.5,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _type = 'Income';
                              _typePage = 1;
                            });
                            _scheduleComputation();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTypeOption({
    required IconData icon,
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : AppColors.textSecondaryOf(context),
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondaryOf(context),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOTAL CARD ───

  Widget _buildTotalCard(double total) {
    final isExpense = _type == 'Expense';
    final mainColor = isExpense ? AppColors.expense : AppColors.income;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              mainColor,
              mainColor.withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: mainColor.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left side — label + period
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isExpense ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Total $_type',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 38),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _tabs[_selectedTab],
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Right side — amount
            Flexible(
              child: Text(
                FormatUtils.formatCurrencyFull(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
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

  // ─── CHART ───

  Widget _buildChartCard(
    List<double> points,
    List<String> labels,
    bool hasData,
  ) {
    if (!hasData) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Container(
          height: 260,
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.borderOf(context).withValues(alpha: 0.5),
            ),
            boxShadow: AppColors.cardShadowOf(context),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceOf(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    size: 40,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No data for this period',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Add some transactions to see your chart',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Smart scaling
    double maxVal = 0.0;
    if (points.isNotEmpty) {
      maxVal = points.reduce((a, b) => a > b ? a : b);
    }
    double roundedMax = _computeNiceMax(maxVal);
    if (roundedMax == 0) {
      roundedMax = 100;
    }

    double interval = roundedMax / 4;
    final barColor = _type == 'Income' ? AppColors.income : AppColors.expense;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.borderOf(context).withValues(alpha: 0.5),
          ),
          boxShadow: AppColors.cardShadowOf(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chart header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_type == 'Expense' ? 'Spending' : 'Earnings'} Trend',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: barColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _getDateRangeLabel(),
                      style: TextStyle(
                        color: barColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Chart
            SizedBox(
              height: 280,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
                child: RepaintBoundary(
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: roundedMax,
                      minY: 0,
                      groupsSpace: _selectedTab == 2 ? 3 : 6,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
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
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 56,
                            interval: interval,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox();
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  '₹${_formatCompactCurrency(value)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= labels.length) {
                                return const SizedBox();
                              }

                              bool shouldShow = false;
                              if (_selectedTab == 0) {
                                shouldShow = idx % 4 == 0;
                              } else if (_selectedTab == 1) {
                                shouldShow = true;
                              } else if (_selectedTab == 2) {
                                shouldShow =
                                    idx == 0 ||
                                    idx % 5 == 0 ||
                                    idx == labels.length - 1;
                              } else {
                                shouldShow = idx % 2 == 0;
                              }

                              if (!shouldShow) return const SizedBox();

                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  labels[idx],
                                  style: TextStyle(
                                    fontSize: _selectedTab == 1 ? 10 : 9,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w600,
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
                            color: AppColors.borderOf(context).withValues(alpha: 0.5),
                            strokeWidth: 1,
                            dashArray: [6, 4],
                          );
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(
                        points.length,
                        (index) => BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: points[index],
                              gradient: LinearGradient(
                                colors: [
                                  barColor,
                                  barColor.withValues(alpha: 0.6),
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              width: _selectedTab == 2 ? 5 : (_selectedTab == 0 ? 8 : 14),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: roundedMax,
                                color: barColor.withValues(alpha: 0.04),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    swapAnimationDuration: const Duration(milliseconds: 300),
                    swapAnimationCurve: Curves.easeOutCubic,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildInsightsRow() {
    final insights = _computeInsights();
    final avgDaily = insights['avgDaily'] as double;
    final highestDay = insights['highestDay'] as String;
    final highestAmount = insights['highestAmount'] as double;
    final txnCount = insights['txnCount'] as int;

    final periodLabel = _selectedTab == 0 ? 'Hourly' : (_selectedTab == 1 ? 'Daily' : (_selectedTab == 2 ? 'Daily' : 'Monthly'));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
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
              icon: Icons.arrow_upward_rounded,
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
      ),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
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
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondaryOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ─── TOP CATEGORIES ───

  Widget _buildTopCategories(
    List<Map<String, dynamic>> topCategories,
    double total,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
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
                'Top ${_type == 'Expense' ? 'Spending' : 'Earning'} Categories',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Category cards
          ...topCategories.asMap().entries.map((entry) {
            final idx = entry.key;
            final cat = entry.value;
            final percentage = total > 0
                ? (cat['amount'] as double) / total * 100
                : 0.0;
            final catColor = AppColors.getCategoryColor(cat['category'] as String);

            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 400 + (idx * 100)),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardOf(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.5),
                  ),
                  boxShadow: AppColors.cardShadowOf(context),
                ),
                child: Row(
                  children: [
                    // Rank badge
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: idx == 0
                            ? const Color(0xFFFFD54F)
                            : idx == 1
                                ? const Color(0xFFB0BEC5)
                                : idx == 2
                                    ? const Color(0xFFBCAAA4)
                                    : Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: idx < 3 ? Colors.white : Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Category icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        cat['icon'] != null
                            ? IconData(
                                // ignore: non_const_argument_for_const_parameter
                                cat['icon'] as int,
                                fontFamily: 'MaterialIcons',
                              )
                            : Icons.category_rounded,
                        color: catColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name + progress bar
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cat['category'] as String,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimaryOf(context),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Gradient progress bar
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
                                      catColor.withValues(alpha: 0.6),
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
                    // Amount + percentage
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
                                : AppColors.textPrimary,
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
      ),
    );
  }
}
