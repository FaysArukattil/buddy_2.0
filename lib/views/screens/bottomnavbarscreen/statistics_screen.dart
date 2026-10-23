// StatisticsScreen — calendar-first analytics.
//
// Layout: teal hero (total + change vs last period + type/period switches)
//   → Overview card (Calendar / Curve / Bars, tap anything to inspect it)
//   → three quick insight tiles
//   → Categories card (donut + tappable ledger).
//
// Behaviour kept from the previous version: debt-preference filter, cached
// transactions, pull-to-refresh, date arrows + pickers, PDF export, and the
// per-category transaction sheet.
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
// ignore: depend_on_referenced_packages
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/utils/icon_helper.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/pdf_service.dart';
import 'package:buddy/services/preference_service.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';
import 'package:buddy/views/widgets/buddy_refresh_control.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => StatisticsScreenState();
}

class StatisticsScreenState extends State<StatisticsScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  // ───────────────────────── State ─────────────────────────

  int _selectedTab = 2; // 0 Day · 1 Week · 2 Month · 3 Year
  String _type = 'Expense';
  final List<String> _tabs = const ['Day', 'Week', 'Month', 'Year'];
  DateTime _selectedDate = DateTime.now();

  int _viewMode = 0; // 0 Calendar · 1 Curve · 2 Bars
  int? _selectedBucket; // shared by calendar + charts
  int _touchedPieIndex = -1;

  bool _isDownloading = false;
  bool _isLoading = true;
  bool _includeDebtsInHome = true;

  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestore = FirestoreService.instance;
  List<Map<String, dynamic>> _rows = [];
  int _dataVersion = 0;

  // Cached computation
  List<double> _cachedPoints = [];
  List<String> _cachedLabels = [];
  double _cachedTotal = 0.0;
  double _cachedPrevTotal = 0.0;
  List<Map<String, dynamic>> _cachedTopCategories = [];
  String _cacheKey = '';

  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> get _activeRows {
    if (_includeDebtsInHome) return _rows;
    return _rows.where((r) {
      final cat = r['category'] as String?;
      return cat != 'Lending' && cat != 'Borrowing';
    }).toList();
  }

  // ───────────────────────── Lifecycle ─────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _includeDebtsInHome = PreferenceService.includeDebtsInHome;
    PreferenceService.includeDebtsInHomeNotifier.addListener(
      _onDebtPrefChanged,
    );

    if (FirestoreService.cachedTransactions.isNotEmpty) {
      _rows = _toRows(FirestoreService.cachedTransactions);
      _dataVersion++;
      _isLoading = false;
      _recompute(); // no setState needed inside initState
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    PreferenceService.includeDebtsInHomeNotifier.removeListener(
      _onDebtPrefChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  void _onDebtPrefChanged() {
    final val = PreferenceService.includeDebtsInHome;
    if (_includeDebtsInHome != val) {
      if (mounted) setState(() => _includeDebtsInHome = val);
      _computeData();
    }
  }

  // ───────────────────────── Data ─────────────────────────

  List<Map<String, dynamic>> _toRows(List txns) {
    return txns
        .map(
          (t) => <String, dynamic>{
            'amount': t.amount,
            'type': t.type,
            'date': t.date.toIso8601String(),
            'category': t.category,
            'icon': t.icon,
            'note': t.note,
            'id': t.id,
          },
        )
        .toList();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    try {
      final txns = await _firestore.getAllTransactions(
        forceRefresh: forceRefresh,
      );
      final rows = _toRows(txns);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _dataVersion++;
        _isLoading = false;
      });
      _computeData();
    } catch (e) {
      debugPrint('❌ STATISTICS: Error loading transactions: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> refreshData() => _load(forceRefresh: true);

  /// Cheap, so we compute immediately (no debounce, nothing gets skipped).
  void _computeData() {
    if (!mounted) return;
    if (_getCacheKey() == _cacheKey) return;
    setState(_recompute);
  }

  void _recompute() {
    _cacheKey = _getCacheKey();
    _cachedPoints = _computePoints();
    _cachedLabels = _computeLabels();
    _cachedTotal = _cachedPoints.fold<double>(0.0, (s, v) => s + v);
    _cachedPrevTotal = _computePreviousTotal();
    _cachedTopCategories = _computeTopCategories();
    _selectedBucket = null;
    _touchedPieIndex = -1;
  }

  String _getCacheKey() =>
      '$_selectedTab-$_type-$_selectedDate-$_dataVersion-$_includeDebtsInHome';

  // ───────────────────────── Period maths ─────────────────────────

  /// [start, end) of the selected period (or the one before it).
  (DateTime, DateTime) _periodRange({bool previous = false}) {
    final d = _selectedDate;
    switch (_selectedTab) {
      case 0:
        final s = DateTime(d.year, d.month, d.day - (previous ? 1 : 0));
        return (s, DateTime(s.year, s.month, s.day + 1));
      case 1:
        final ws = DateTime(
          d.year,
          d.month,
          d.day - ((d.weekday - 1) % 7) - (previous ? 7 : 0),
        );
        return (ws, DateTime(ws.year, ws.month, ws.day + 7));
      case 2:
        final s = DateTime(d.year, d.month - (previous ? 1 : 0), 1);
        return (s, DateTime(s.year, s.month + 1, 1));
      default:
        final s = DateTime(d.year - (previous ? 1 : 0), 1, 1);
        return (s, DateTime(s.year + 1, 1, 1));
    }
  }

  bool _isDateInCurrentPeriod(DateTime dt) {
    final (s, e) = _periodRange();
    return !dt.isBefore(s) && dt.isBefore(e);
  }

  bool _matchesType(Map<String, dynamic> r) {
    final type = (r['type'] as String).toLowerCase().trim();
    return _type == 'Income' ? type == 'income' : type == 'expense';
  }

  int _bucketCount() {
    switch (_selectedTab) {
      case 0:
        return 24;
      case 1:
        return 7;
      case 2:
        return DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
      default:
        return 12;
    }
  }

  int _bucketIndex(DateTime dt) {
    switch (_selectedTab) {
      case 0:
        return dt.hour;
      case 1:
        return (dt.weekday - 1) % 7;
      case 2:
        return dt.day - 1;
      default:
        return dt.month - 1;
    }
  }

  DateTime _bucketStart(int i) {
    final d = _selectedDate;
    switch (_selectedTab) {
      case 0:
        return DateTime(d.year, d.month, d.day, i);
      case 1:
        final s = d.subtract(Duration(days: (d.weekday - 1) % 7));
        return DateTime(s.year, s.month, s.day + i);
      case 2:
        return DateTime(d.year, d.month, i + 1);
      default:
        return DateTime(d.year, i + 1, 1);
    }
  }

  bool _isCurrentBucket(int i, DateTime now) {
    final s = _bucketStart(i);
    switch (_selectedTab) {
      case 0:
        return s.year == now.year &&
            s.month == now.month &&
            s.day == now.day &&
            s.hour == now.hour;
      case 3:
        return s.year == now.year && s.month == now.month;
      default:
        return s.year == now.year && s.month == now.month && s.day == now.day;
    }
  }

  String _bucketLabel(int i) {
    final s = _bucketStart(i);
    switch (_selectedTab) {
      case 0:
        return '${DateFormat('MMM d').format(s)} • ${DateFormat('h a').format(s)}';
      case 3:
        return DateFormat('MMMM yyyy').format(s);
      default:
        return DateFormat('EEE, MMM d').format(s);
    }
  }

  List<Map<String, dynamic>> _txnsForBucket(int i) {
    final list = _activeRows.where((r) {
      if (!_matchesType(r)) return false;
      final dt = DateTime.tryParse(r['date'] as String);
      return dt != null && _isDateInCurrentPeriod(dt) && _bucketIndex(dt) == i;
    }).toList();
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
  }

  // ───────────────────────── Computation ─────────────────────────

  List<double> _computePoints() {
    final buckets = List<double>.filled(_bucketCount(), 0);
    for (final r in _activeRows) {
      if (!_matchesType(r)) continue;
      final dt = DateTime.tryParse(r['date'] as String);
      if (dt == null || !_isDateInCurrentPeriod(dt)) continue;
      buckets[_bucketIndex(dt)] += (r['amount'] as num).toDouble();
    }
    return buckets;
  }

  List<String> _computeLabels() {
    switch (_selectedTab) {
      case 0:
        return List.generate(24, (i) => '$i:00');
      case 1:
        return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      case 2:
        return List.generate(_bucketCount(), (i) => '${i + 1}');
      default:
        return const [
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
    }
  }

  double _computePreviousTotal() {
    final (s, e) = _periodRange(previous: true);
    double sum = 0;
    for (final r in _activeRows) {
      if (!_matchesType(r)) continue;
      final dt = DateTime.tryParse(r['date'] as String);
      if (dt == null || dt.isBefore(s) || !dt.isBefore(e)) continue;
      sum += (r['amount'] as num).toDouble();
    }
    return sum;
  }

  List<Map<String, dynamic>> _computeTopCategories() {
    final totals = <String, double>{};
    final counts = <String, int>{};
    final icons = <String, int>{};

    for (final r in _activeRows) {
      if (!_matchesType(r)) continue;
      final dt = DateTime.tryParse(r['date'] as String);
      if (dt == null || !_isDateInCurrentPeriod(dt)) continue;

      final cat = (r['category'] as String?)?.trim() ?? 'Other';
      totals[cat] = (totals[cat] ?? 0) + (r['amount'] as num).toDouble();
      counts[cat] = (counts[cat] ?? 0) + 1;
      final icon = r['icon'] as int?;
      if (icon != null && !icons.containsKey(cat)) icons[cat] = icon;
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .where((e) => e.value > 0)
        .map(
          (e) => <String, dynamic>{
            'category': e.key,
            'amount': e.value,
            'count': counts[e.key] ?? 1,
            'icon': icons[e.key],
          },
        )
        .toList();
  }

  /// Buckets (hours/days/months) that have passed so far in the period, so the
  /// average isn't dragged down by days still in the future.
  int _elapsedBuckets(int totalBuckets) {
    final now = DateTime.now();
    var elapsed = totalBuckets;
    if (_isDateInCurrentPeriod(now)) {
      switch (_selectedTab) {
        case 0:
          elapsed = now.hour + 1;
          break;
        case 1:
          elapsed = now.weekday;
          break;
        case 2:
          elapsed = now.day;
          break;
        default:
          elapsed = now.month;
      }
    }
    return elapsed.clamp(1, math.max(1, totalBuckets));
  }

  // ───────────────────────── Formatting ─────────────────────────

  String _money(double v) => FormatUtils.formatCurrency(v, compact: true);

  String _compact(double value) {
    if (value >= 10000000) return '${(value / 10000000).toStringAsFixed(1)}Cr';
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  String _getDateRangeLabel() {
    final d = _selectedDate;
    switch (_selectedTab) {
      case 0:
        return DateFormat('MMM dd, yyyy').format(d);
      case 1:
        final (s, e) = _periodRange();
        final end = e.subtract(const Duration(days: 1));
        return '${DateFormat('MMM dd').format(s)} – ${DateFormat('MMM dd').format(end)}';
      case 2:
        return DateFormat('MMMM yyyy').format(d);
      default:
        return DateFormat('yyyy').format(d);
    }
  }

  /// Rounds the chart max up so all 4 grid lines land on whole, round numbers.
  double _niceMax(double val) {
    if (val <= 0) return 100;
    final raw = val / 4;
    final magnitude = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final norm = raw / magnitude;
    double step;
    if (norm <= 1) {
      step = 1;
    } else if (norm <= 2) {
      step = 2;
    } else if (norm <= 2.5 && magnitude >= 10) {
      step = 2.5;
    } else if (norm <= 5) {
      step = 5;
    } else {
      step = 10;
    }
    step *= magnitude;
    if (step < 1) step = 1;
    return step * 4;
  }

  // ───────────────────────── Navigation ─────────────────────────

  bool get _canNavigateForward {
    final (_, e) = _periodRange();
    return e.isBefore(DateTime.now()) || e.isAtSameMomentAs(DateTime.now());
  }

  void _navigateDate(int delta) {
    HapticFeedback.selectionClick();
    final c = _selectedDate;
    DateTime next;
    switch (_selectedTab) {
      case 0:
        next = DateTime(c.year, c.month, c.day + delta);
        break;
      case 1:
        next = DateTime(c.year, c.month, c.day + 7 * delta);
        break;
      case 2:
        final maxDays = DateTime(c.year, c.month + delta + 1, 0).day;
        next = DateTime(c.year, c.month + delta, math.min(c.day, maxDays));
        break;
      default:
        next = DateTime(c.year + delta, c.month, math.min(c.day, 28));
    }
    final today = DateTime.now();
    if (next.isAfter(today)) next = today;
    setState(() => _selectedDate = next);
    _computeData();
  }

  void _selectTab(int i) {
    setState(() {
      _selectedTab = i;
      _selectedDate = DateTime.now();
    });
    _computeData();
  }

  void _selectType(int i) {
    setState(() => _type = i == 0 ? 'Expense' : 'Income');
    _computeData();
  }

  // ───────────────────────── PDF export ─────────────────────────

  Future<void> _downloadCurrentView() async {
    setState(() => _isDownloading = true);
    try {
      final (start, end) = _periodRange();
      final txns = _activeRows.where((t) {
        final d = DateTime.tryParse(t['date'] as String);
        return d != null && !d.isBefore(start) && d.isBefore(end);
      }).toList();

      const titles = [
        'Daily Report',
        'Weekly Report',
        'Monthly Report',
        'Yearly Report',
      ];

      if (txns.isEmpty) {
        if (!mounted) return;
        AppSnackbar.showInfo(context, 'No transactions found for this period');
        return;
      }

      final file = await PdfService.generateMultipleTransactionsPdf(
        transactions: txns,
        title: titles[_selectedTab],
        subtitle: _getDateRangeLabel(),
      );
      if (!mounted) return;
      _showPdfOptions(file);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Error generating PDF: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showPdfOptions(file) {
    Widget option(
      IconData icon,
      Color color,
      String label,
      VoidCallback onTap,
    ) {
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Report ready',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 12),
            option(
              Icons.open_in_new_rounded,
              AppColors.primary,
              'Open PDF',
              () => PdfService.openPdf(file),
            ),
            option(
              Icons.share_rounded,
              AppColors.secondary,
              'Share PDF',
              () => PdfService.sharePdf(file),
            ),
            option(
              Icons.print_rounded,
              AppColors.income,
              'Print PDF',
              () => PdfService.printPdf(file),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Pickers ─────────────────────────

  Future<void> _showDatePicker() async {
    HapticFeedback.lightImpact();
    switch (_selectedTab) {
      case 0:
      case 1:
        await _pickDate(
          title: _selectedTab == 0 ? 'Select day' : 'Select week',
          mode: CupertinoDatePickerMode.date,
        );
        break;
      case 2:
        await _pickDate(
          title: 'Select month',
          mode: CupertinoDatePickerMode.monthYear,
        );
        break;
      default:
        await _pickYear();
    }
  }

  Future<void> _pickDate({
    required String title,
    required CupertinoDatePickerMode mode,
  }) {
    DateTime temp = _selectedDate;
    return _showPickerSheet(
      title: title,
      onDone: () {
        setState(() => _selectedDate = temp);
        _computeData();
      },
      picker: CupertinoDatePicker(
        mode: mode,
        initialDateTime: _selectedDate,
        maximumDate: DateTime.now(),
        onDateTimeChanged: (date) => temp = date,
      ),
    );
  }

  Future<void> _pickYear() {
    final currentYear = DateTime.now().year;
    int selectedYear = _selectedDate.year;
    return _showPickerSheet(
      title: 'Select year',
      onDone: () {
        setState(() => _selectedDate = DateTime(selectedYear, 1, 1));
        _computeData();
      },
      picker: Builder(
        builder: (context) => CupertinoPicker(
          scrollController: FixedExtentScrollController(
            initialItem: currentYear - selectedYear,
          ),
          itemExtent: 40,
          onSelectedItemChanged: (index) => selectedYear = currentYear - index,
          children: List.generate(currentYear - 2020 + 1, (index) {
            return Center(
              child: Text(
                (currentYear - index).toString(),
                style: TextStyle(
                  fontSize: 22,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Future<void> _showPickerSheet({
    required String title,
    required Widget picker,
    required VoidCallback onDone,
  }) {
    return showCupertinoModalPopup(
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
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderOf(context)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    CupertinoButton(
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        onDone();
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
                  child: picker,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────── Build ─────────────────────────

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
        body: const Center(child: BuddyLoadingIndicator(size: 56)),
      );
    }

    final total = _cachedTotal;
    final hasData = total > 0;
    final accent = _type == 'Expense' ? AppColors.expense : AppColors.income;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: Stack(
        children: [
          // Fills the space revealed when over-scrolling at the top.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _scrollController,
              builder: (context, _) {
                final offset = _scrollController.hasClients
                    ? _scrollController.offset
                    : 0.0;
                if (offset >= 0) return const SizedBox.shrink();
                return Container(
                  height: topPadding - offset + 40,
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
              SliverToBoxAdapter(child: _buildHero(isDark, topPadding)),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  mq.padding.bottom + kBottomNavigationBarHeight + 60,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    !hasData
                        ? [_buildEmptyState()]
                        : [
                            _buildOverviewCard(accent, isDark),
                            const SizedBox(height: 14),
                            _buildInsightTiles(),
                            const SizedBox(height: 14),
                            _buildCategoriesCard(isDark),
                          ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Hero ─────────────────────────

  Widget _buildHero(bool isDark, double topPadding) {
    final isExpense = _type == 'Expense';
    final total = _cachedTotal;
    final prev = _cachedPrevTotal;
    final hasPrev = prev > 0;
    final deltaPct = hasPrev ? (total - prev) / prev * 100 : 0.0;
    final isUp = deltaPct >= 0;
    final good = isExpense ? !isUp : isUp;
    final badge = good ? const Color(0xFF69F0AE) : const Color(0xFFFF8A80);
    const compareNames = ['yesterday', 'last week', 'last month', 'last year'];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPadding + 12, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF0F2624), Color(0xFF1E5D57)]
              : const [Color(0xFF0F3632), Color(0xFF2C7A72)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + export
          Row(
            children: [
              const Text(
                'Statistics',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _isDownloading ? null : _downloadCurrentView,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Center(
                    child: _isDownloading
                        ? const BuddyLoadingIndicator(size: 16)
                        : const Icon(
                            Icons.ios_share_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Date navigator
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                _navButton(Icons.chevron_left_rounded, () => _navigateDate(-1)),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showDatePicker,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _getDateRangeLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
                _navButton(
                  Icons.chevron_right_rounded,
                  _canNavigateForward ? () => _navigateDate(1) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Total + change
          Row(
            children: [
              Text(
                isExpense ? 'Total spent' : 'Total earned',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (hasPrev)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badge.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUp
                            ? Icons.north_east_rounded
                            : Icons.south_east_rounded,
                        size: 12,
                        color: badge,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${deltaPct.abs().toStringAsFixed(1)}% vs ${compareNames[_selectedTab]}',
                        style: TextStyle(
                          color: badge,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              FormatUtils.formatCurrencyFull(total),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Switches
          _GlassSegmented(
            labels: const ['Expense', 'Income'],
            icons: const [Icons.south_west_rounded, Icons.north_east_rounded],
            selected: isExpense ? 0 : 1,
            onChanged: _selectType,
            activeColor: isExpense
                ? const Color(0xFFE57373)
                : const Color(0xFF4DB6AC),
          ),
          const SizedBox(height: 10),
          _GlassSegmented(
            labels: _tabs,
            selected: _selectedTab,
            onChanged: _selectTab,
            height: 40,
            fontSize: 12.5,
          ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(
          icon,
          size: 24,
          color: onTap == null ? Colors.white30 : Colors.white,
        ),
      ),
    );
  }

  // ───────────────────────── Overview card ─────────────────────────

  BoxDecoration _cardDecoration([double radius = 24]) => BoxDecoration(
    color: AppColors.cardOf(context),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: AppColors.borderOf(context).withValues(alpha: 0.5),
    ),
    boxShadow: AppColors.cardShadowOf(context),
  );

  Widget _buildOverviewCard(Color accent, bool isDark) {
    final points = _cachedPoints;
    final labels = _cachedLabels;

    Widget body;
    switch (_viewMode) {
      case 1:
        body = _buildLineChart(points, labels, accent, isDark);
        break;
      case 2:
        body = _buildBarChart(points, labels, accent, isDark);
        break;
      default:
        body = _buildCalendar(points, accent);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _viewMode == 0
                      ? 'Activity'
                      : (_type == 'Expense'
                            ? 'Spending trend'
                            : 'Earnings trend'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              _buildViewToggle(accent),
            ],
          ),
          const SizedBox(height: 14),
          _buildReadout(accent),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  Widget _buildViewToggle(Color accent) {
    const icons = [
      Icons.calendar_month_rounded,
      Icons.show_chart_rounded,
      Icons.bar_chart_rounded,
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(icons.length, (i) {
          final sel = _viewMode == i;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _viewMode = i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: sel
                    ? accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icons[i],
                size: 18,
                color: sel ? accent : AppColors.textSecondaryOf(context),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Shows whatever is selected in the calendar / chart.
  Widget _buildReadout(Color accent) {
    final idx = _selectedBucket;
    final points = _cachedPoints;
    final has = idx != null && idx < points.length;
    final unit = _selectedTab == 0
        ? 'an hour'
        : (_selectedTab == 3 ? 'a month' : 'a day');

    if (!has) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 16,
              color: AppColors.textSecondaryOf(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Tap $unit to see what you ${_type == 'Expense' ? 'spent' : 'earned'}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      );
    }

    final amount = points[idx];
    final pct = _cachedTotal > 0 ? amount / _cachedTotal * 100 : 0.0;
    final count = amount > 0 ? _txnsForBucket(idx).length : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bucketLabel(idx),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        amount > 0
                            ? FormatUtils.formatCurrencyFull(amount)
                            : 'Nothing recorded',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: amount > 0 ? 18 : 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: amount > 0
                              ? accent
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                    if (amount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${pct.toStringAsFixed(1)}% of total',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (count > 0)
            TextButton(
              onPressed: () => _showTransactionsSheet(
                title: _bucketLabel(idx),
                subtitle:
                    '$count ${count == 1 ? 'transaction' : 'transactions'}',
                txns: _txnsForBucket(idx),
                color: accent,
                icon: Icons.event_note_rounded,
                showCategory: true,
              ),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────── Calendar ─────────────────────────

  Widget _buildCalendar(List<double> points, Color accent) {
    final maxVal = points.isEmpty ? 0.0 : points.reduce(math.max);
    final now = DateTime.now();

    Widget cell(int i, String label, {String? sub, double height = 42}) {
      final val = points[i];
      final intensity = (maxVal > 0 && val > 0)
          ? (val / maxVal).clamp(0.2, 1.0).toDouble()
          : 0.0;
      final future = _bucketStart(i).isAfter(now);
      final selected = _selectedBucket == i;
      final today = _isCurrentBucket(i, now);
      final onFill = intensity > 0.55;
      final textColor = onFill
          ? Colors.white
          : (future
                ? AppColors.textSecondaryOf(context).withValues(alpha: 0.45)
                : AppColors.textPrimaryOf(context));

      return Padding(
        padding: const EdgeInsets.all(2.5),
        child: GestureDetector(
          onTap: future
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedBucket = selected ? null : i);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: height,
            decoration: BoxDecoration(
              color: intensity > 0
                  ? accent.withValues(alpha: intensity)
                  : AppColors.surfaceOf(
                      context,
                    ).withValues(alpha: future ? 0.45 : 1.0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.textPrimaryOf(context)
                    : (today
                          ? AppColors.textSecondaryOf(
                              context,
                            ).withValues(alpha: 0.7)
                          : Colors.transparent),
                width: selected ? 2 : 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: (onFill || today || selected)
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: onFill
                            ? Colors.white.withValues(alpha: 0.85)
                            : AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget grid(int columns, List<Widget?> cells) {
      final rows = <Widget>[];
      for (var i = 0; i < cells.length; i += columns) {
        final slice = cells.sublist(i, math.min(i + columns, cells.length));
        rows.add(
          Row(
            children: List.generate(columns, (c) {
              final w = c < slice.length ? slice[c] : null;
              return Expanded(child: w ?? const SizedBox());
            }),
          ),
        );
      }
      return Column(children: rows);
    }

    Widget content;
    switch (_selectedTab) {
      case 1: // Week: one row, name + amount
        content = grid(7, [
          for (var i = 0; i < 7; i++)
            cell(
              i,
              _cachedLabels[i],
              sub: points[i] > 0 ? _compact(points[i]) : '–',
              height: 66,
            ),
        ]);
        break;
      case 0: // Day: 24 hours
        String hour(int h) => h == 0
            ? '12a'
            : (h < 12 ? '${h}a' : (h == 12 ? '12p' : '${h - 12}p'));
        content = grid(6, [
          for (var i = 0; i < 24; i++) cell(i, hour(i), height: 40),
        ]);
        break;
      case 3: // Year: 12 months
        content = grid(4, [
          for (var i = 0; i < 12; i++)
            cell(
              i,
              _cachedLabels[i],
              sub: points[i] > 0 ? _compact(points[i]) : '–',
              height: 58,
            ),
        ]);
        break;
      default: // Month: real calendar, aligned to weekdays
        final lead =
            DateTime(_selectedDate.year, _selectedDate.month, 1).weekday - 1;
        content = Column(
          children: [
            Row(
              children: [
                for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            grid(7, [
              for (var i = 0; i < lead; i++) null,
              for (var i = 0; i < points.length; i++) cell(i, '${i + 1}'),
            ]),
          ],
        );
    }

    return GestureDetector(
      // Swipe the calendar to move between periods.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -350 && _canNavigateForward) {
          _navigateDate(1);
        } else if (v > 350) {
          _navigateDate(-1);
        }
      },
      child: Column(
        children: [
          content,
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Less',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(width: 6),
              for (final a in const [0.2, 0.4, 0.6, 0.8, 1.0])
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: a),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 3),
              Text(
                'More',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Charts ─────────────────────────

  bool _showAxisLabel(int idx, int count) {
    switch (_selectedTab) {
      case 0:
        return idx % 4 == 0;
      case 1:
        return true;
      case 2:
        return idx == 0 || idx % 5 == 0 || idx == count - 1;
      default:
        return idx % 2 == 0;
    }
  }

  FlTitlesData _titles(List<String> labels, double interval, Color accent) {
    return FlTitlesData(
      show: true,
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 50,
          interval: interval,
          getTitlesWidget: (value, meta) {
            if (value == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '₹${_compact(value)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryOf(context),
                ),
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
            if (idx < 0 ||
                idx >= labels.length ||
                !_showAxisLabel(idx, labels.length)) {
              return const SizedBox.shrink();
            }
            final sel = _selectedBucket == idx;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                labels[idx],
                style: TextStyle(
                  fontSize: _selectedTab == 1 ? 10 : 9,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  color: sel ? accent : AppColors.textSecondaryOf(context),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  FlGridData _grid(double interval) {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (value) => FlLine(
        color: AppColors.borderOf(context).withValues(alpha: 0.35),
        strokeWidth: 1,
        dashArray: [6, 4],
      ),
    );
  }

  Widget _buildLineChart(
    List<double> points,
    List<String> labels,
    Color accent,
    bool isDark,
  ) {
    final maxY = _niceMax(points.isEmpty ? 0 : points.reduce(math.max));
    final interval = maxY / 4;

    return SizedBox(
      height: 230,
      child: RepaintBoundary(
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(0, points.length - 1).toDouble(),
            minY: 0,
            maxY: maxY,
            gridData: _grid(interval),
            borderData: FlBorderData(show: false),
            titlesData: _titles(labels, interval, accent),
            lineTouchData: LineTouchData(
              handleBuiltInTouches: false,
              touchSpotThreshold: 28,
              touchCallback: (event, response) {
                final spots = response?.lineBarSpots;
                if (!event.isInterestedForInteractions ||
                    spots == null ||
                    spots.isEmpty) {
                  return;
                }
                final i = spots.first.spotIndex;
                if (_selectedBucket != i) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedBucket = i);
                }
              },
              getTouchedSpotIndicator: (barData, spotIndexes) {
                return spotIndexes.map((i) {
                  return TouchedSpotIndicatorData(
                    FlLine(
                      color: accent.withValues(alpha: 0.6),
                      strokeWidth: 1.5,
                      dashArray: [4, 4],
                    ),
                    FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                            radius: 6,
                            color: Colors.white,
                            strokeWidth: 3,
                            strokeColor: accent,
                          ),
                    ),
                  );
                }).toList();
              },
            ),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(
                  points.length,
                  (i) => FlSpot(i.toDouble(), points[i]),
                ),
                isCurved: true,
                curveSmoothness: 0.32,
                preventCurveOverShooting: true,
                color: accent,
                barWidth: 3,
                isStrokeCapRound: true,
                showingIndicators: _selectedBucket != null
                    ? [_selectedBucket!]
                    : [],
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: isDark ? 0.35 : 0.24),
                      accent.withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }

  Widget _buildBarChart(
    List<double> points,
    List<String> labels,
    Color accent,
    bool isDark,
  ) {
    final maxY = _niceMax(points.isEmpty ? 0 : points.reduce(math.max));
    final interval = maxY / 4;
    final barWidth = _selectedTab == 2 ? 5.5 : (_selectedTab == 0 ? 8.0 : 14.0);

    return SizedBox(
      height: 230,
      child: RepaintBoundary(
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            minY: 0,
            gridData: _grid(interval),
            borderData: FlBorderData(show: false),
            titlesData: _titles(labels, interval, accent),
            barTouchData: BarTouchData(
              enabled: true,
              touchCallback: (event, response) {
                final spot = response?.spot;
                if (!event.isInterestedForInteractions || spot == null) return;
                final i = spot.touchedBarGroupIndex;
                if (_selectedBucket != i) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedBucket = i);
                }
              },
              // The readout above replaces the tooltip.
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (group) => Colors.transparent,
                tooltipPadding: EdgeInsets.zero,
                tooltipMargin: 0,
                getTooltipItem: (group, gi, rod, ri) =>
                    BarTooltipItem('', const TextStyle(fontSize: 0)),
              ),
            ),
            barGroups: List.generate(points.length, (i) {
              final sel = _selectedBucket == i;
              final dim = _selectedBucket != null && !sel;
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i],
                    width: barWidth,
                    color: accent.withValues(alpha: dim ? 0.3 : 1.0),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: accent.withValues(alpha: 0.05),
                    ),
                  ),
                ],
              );
            }),
          ),
          swapAnimationDuration: const Duration(milliseconds: 300),
          swapAnimationCurve: Curves.easeOutCubic,
        ),
      ),
    );
  }

  // ───────────────────────── Insights ─────────────────────────

  Widget _buildInsightTiles() {
    final points = _cachedPoints;
    final total = _cachedTotal;
    final peakVal = points.isEmpty ? 0.0 : points.reduce(math.max);
    final peakIdx = points.indexOf(peakVal);
    final peakLabel = peakIdx >= 0 && peakIdx < _cachedLabels.length
        ? _cachedLabels[peakIdx]
        : '-';
    final avg = total / _elapsedBuckets(points.length);
    final activeUnits = points.where((p) => p > 0).length;

    final (s, e) = _periodRange();
    final txnCount = _activeRows.where((r) {
      if (!_matchesType(r)) return false;
      final d = DateTime.tryParse(r['date'] as String);
      return d != null && !d.isBefore(s) && d.isBefore(e);
    }).length;

    const unit = ['hour', 'day', 'day', 'month'];

    return Row(
      children: [
        Expanded(
          child: _tile(
            Icons.speed_rounded,
            const Color(0xFF5C6BC0),
            _money(avg),
            'Avg per ${unit[_selectedTab]}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tile(
            Icons.bolt_rounded,
            const Color(0xFFFF7043),
            _money(peakVal),
            'Peak · $peakLabel',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tile(
            Icons.receipt_long_rounded,
            const Color(0xFF26A69A),
            '$txnCount',
            '$activeUnits active ${unit[_selectedTab]}${activeUnits == 1 ? '' : 's'}',
          ),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Categories ─────────────────────────

  Widget _buildCategoriesCard(bool isDark) {
    final cats = _cachedTopCategories;
    final total = _cachedTotal;
    if (cats.isEmpty) return const SizedBox.shrink();

    final touched = (_touchedPieIndex >= 0 && _touchedPieIndex < cats.length)
        ? cats[_touchedPieIndex]
        : null;

    final centerTitle = touched != null
        ? touched['category'] as String
        : 'Total';
    final centerValue = _money(
      touched != null ? touched['amount'] as double : total,
    );
    final centerColor = touched != null
        ? AppColors.getCategoryColor(touched['category'] as String)
        : AppColors.textPrimaryOf(context);
    final centerSub = touched != null
        ? '${((touched['amount'] as double) / total * 100).toStringAsFixed(1)}%'
        : '${cats.length} ${cats.length == 1 ? 'category' : 'categories'}';

    return Container(
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Text(
              'Categories',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
          SizedBox(
            height: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 3,
                    centerSpaceRadius: 62,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        final section = response?.touchedSection;
                        if (!event.isInterestedForInteractions ||
                            section == null) {
                          return;
                        }
                        final i = section.touchedSectionIndex;
                        if (i >= 0 && i != _touchedPieIndex) {
                          HapticFeedback.selectionClick();
                          setState(() => _touchedPieIndex = i);
                        }
                      },
                    ),
                    sections: List.generate(cats.length, (i) {
                      final cat = cats[i];
                      final amt = cat['amount'] as double;
                      final pct = total > 0 ? amt / total * 100 : 0.0;
                      final isTouched = i == _touchedPieIndex;
                      return PieChartSectionData(
                        color: AppColors.getCategoryColor(
                          cat['category'] as String,
                        ),
                        value: amt,
                        radius: isTouched ? 34 : 26,
                        title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                        titleStyle: TextStyle(
                          fontSize: isTouched ? 12 : 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        centerValue,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: centerColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        centerSub,
                        style: TextStyle(
                          fontSize: 11,
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
          Divider(
            height: 1,
            thickness: 0.6,
            color: AppColors.borderOf(context).withValues(alpha: 0.6),
          ),
          for (var i = 0; i < cats.length; i++) ...[
            _categoryRow(i, cats[i], total),
            if (i != cats.length - 1)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: 70,
                endIndent: 16,
                color: AppColors.borderOf(context).withValues(alpha: 0.4),
              ),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow(int idx, Map<String, dynamic> cat, double total) {
    final name = cat['category'] as String;
    final amt = cat['amount'] as double;
    final count = (cat['count'] as int?) ?? 1;
    final pct = total > 0 ? amt / total * 100 : 0.0;
    final color = AppColors.getCategoryColor(name);
    final highlighted = idx == _touchedPieIndex;
    final isLast = idx == _cachedTopCategories.length - 1;

    return Material(
      color: highlighted ? color.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(24))
          : BorderRadius.zero,
      child: InkWell(
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(24))
            : BorderRadius.zero,
        onTap: () {
          HapticFeedback.lightImpact();
          final txns = _txnsForCategory(name);
          _showTransactionsSheet(
            title: name,
            subtitle:
                '$count ${count == 1 ? 'transaction' : 'transactions'} • ${_getDateRangeLabel()}',
            txns: txns,
            color: color,
            icon: IconHelper.getIcon(cat['icon']),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  IconHelper.getIcon(cat['icon']),
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        Text(
                          _money(amt),
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: SizedBox(
                              height: 5,
                              child: LinearProgressIndicator(
                                value: (pct / 100).clamp(0.0, 1.0),
                                backgroundColor: AppColors.surfaceOf(context),
                                valueColor: AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${pct.toStringAsFixed(1)}% · $count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _txnsForCategory(String name) {
    final list = _activeRows.where((r) {
      if (!_matchesType(r)) return false;
      final cat = (r['category'] as String?)?.trim() ?? 'Other';
      if (cat != name) return false;
      final dt = DateTime.tryParse(r['date'] as String);
      return dt != null && _isDateInCurrentPeriod(dt);
    }).toList();
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
  }

  // ───────────────────────── Empty state ─────────────────────────

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 24),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              size: 34,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No ${_type == 'Expense' ? 'expenses' : 'income'} here',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use the arrows above to look at another period.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Transactions sheet ─────────────────────────

  void _showTransactionsSheet({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> txns,
    required Color color,
    required IconData icon,
    bool showCategory = false,
  }) {
    HapticFeedback.lightImpact();
    final totalAmt = txns.fold<double>(
      0.0,
      (sum, r) => sum + (r['amount'] as num).toDouble(),
    );
    final valueColor = _type == 'Income'
        ? AppColors.income
        : AppColors.textPrimaryOf(context);

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
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(ctx),
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
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: AppColors.textPrimaryOf(ctx),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondaryOf(ctx),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      FormatUtils.formatCurrencyFull(totalAmt),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: valueColor,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 0.6,
                color: AppColors.borderOf(ctx).withValues(alpha: 0.6),
              ),
              Flexible(
                child: txns.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No transactions found.',
                          style: TextStyle(
                            color: AppColors.textSecondaryOf(ctx),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        itemCount: txns.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final item = txns[i];
                          final dt = DateTime.tryParse(item['date'] as String);
                          final date = dt != null
                              ? DateFormat('MMM dd, hh:mm a').format(dt)
                              : '';
                          final note = (item['note'] as String?)?.trim() ?? '';
                          final cat =
                              (item['category'] as String?)?.trim() ?? 'Other';
                          final rowTitle = note.isNotEmpty ? note : cat;
                          final rowSub = (showCategory && note.isNotEmpty)
                              ? '$cat • $date'
                              : date;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rowTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        rowSub,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  FormatUtils.formatCurrencyFull(
                                    (item['amount'] as num).toDouble(),
                                  ),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: valueColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              SizedBox(height: 16 + MediaQuery.of(ctx).padding.bottom),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Glass segmented control ─────────────────────────

/// A swipeable / tappable segmented control styled for the teal hero.
class _GlassSegmented extends StatefulWidget {
  const _GlassSegmented({
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.icons,
    this.activeColor,
    this.height = 42,
    this.fontSize = 13,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final int selected;
  final ValueChanged<int> onChanged;
  final Color? activeColor;
  final double height;
  final double fontSize;

  @override
  State<_GlassSegmented> createState() => _GlassSegmentedState();
}

class _GlassSegmentedState extends State<_GlassSegmented> {
  double? _drag; // fractional page while the finger is dragging

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;

    return Container(
      height: widget.height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final itemW = c.maxWidth / n;
          final page = _drag ?? widget.selected.toDouble();

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) {
              final start = _drag ?? widget.selected.toDouble();
              setState(() {
                _drag = (start + d.delta.dx / itemW)
                    .clamp(0.0, n - 1.0)
                    .toDouble();
              });
            },
            onHorizontalDragEnd: (_) {
              final target = (_drag ?? widget.selected.toDouble()).round();
              setState(() => _drag = null);
              if (target != widget.selected) {
                HapticFeedback.selectionClick();
                widget.onChanged(target);
              }
            },
            onHorizontalDragCancel: () => setState(() => _drag = null),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: _drag != null
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: page * itemW,
                  top: 0,
                  bottom: 0,
                  width: itemW,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color:
                          widget.activeColor ??
                          Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(n, (i) {
                    final sel = (page - i).abs() < 0.5;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i != widget.selected) {
                            HapticFeedback.selectionClick();
                            widget.onChanged(i);
                          }
                        },
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icons != null) ...[
                                Icon(
                                  widget.icons![i],
                                  size: 15,
                                  color: sel ? Colors.white : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                widget.labels[i],
                                style: TextStyle(
                                  fontSize: widget.fontSize,
                                  fontWeight: sel
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: sel ? Colors.white : Colors.white70,
                                ),
                              ),
                            ],
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
}
