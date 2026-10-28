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
import 'dart:async';
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
import 'package:buddy/views/screens/transaction_detail_screen.dart';

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

  int? _selectedBucket; // selected calendar cell
  int _touchedPieIndex = -1;
  int _lastSliceTapTime = 0;

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
  List<Map<String, dynamic>> _cachedTxns =
      []; // this period + type, oldest first
  String _cacheKey = '';

  // Dual-view PageView controller & auto-cycle timer
  static const int _kHeroVisualLoopBase = 2000;
  late final PageController _heroVisualPageController;
  int _heroVisualIndex = 0; // 0 = Chart, 1 = Calendar
  Timer? _heroAutoCycleTimer;
  bool _userInteractedWithHero = false;
  double _heroDragAccumX = 0;
  double _heroDragStartPage = 0;
  int _lastHeroHapticIndex = 0;

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
    _heroVisualPageController = PageController(
      initialPage: _kHeroVisualLoopBase + _heroVisualIndex,
    );
    _includeDebtsInHome = PreferenceService.includeDebtsInHome;
    _startHeroAutoCycleTimer();
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
    _heroAutoCycleTimer?.cancel();
    _heroVisualPageController.dispose();
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

  // ───────────────────────── Auto-cycle ─────────────────────────

  void _startHeroAutoCycleTimer() {
    _heroAutoCycleTimer?.cancel();
    if (_userInteractedWithHero) return;
    _heroAutoCycleTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted || _userInteractedWithHero) {
        timer.cancel();
        return;
      }
      if (_heroVisualPageController.hasClients &&
          _heroVisualPageController.positions.length == 1 &&
          _heroVisualPageController.position.haveDimensions) {
        final double currentP = _heroVisualPageController.page ??
            (_kHeroVisualLoopBase + _heroVisualIndex).toDouble();
        _onToggleVisualModeIndex(currentP.round() + 1, isUserAction: false);
      }
    });
  }

  void _stopAutoCycle() {
    if (!_userInteractedWithHero) {
      _userInteractedWithHero = true;
      _heroAutoCycleTimer?.cancel();
      _heroAutoCycleTimer = null;
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
    _cachedTxns = _computePeriodTxns();
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

  List<Map<String, dynamic>> _computePeriodTxns() {
    final list = <Map<String, dynamic>>[];
    for (final r in _activeRows) {
      if (!_matchesType(r)) continue;
      final dt = DateTime.tryParse(r['date'] as String);
      if (dt == null || !_isDateInCurrentPeriod(dt)) continue;
      list.add(r);
    }
    list.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return list;
  }

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
    final now = DateTime.now();
    switch (_selectedTab) {
      case 0:
        if (d.year == now.year && d.month == now.month && d.day == now.day) {
          return 'Today, ${DateFormat('MMM d').format(d)}';
        }
        final yesterday = now.subtract(const Duration(days: 1));
        if (d.year == yesterday.year &&
            d.month == yesterday.month &&
            d.day == yesterday.day) {
          return 'Yesterday, ${DateFormat('MMM d').format(d)}';
        }
        return DateFormat('EEE, MMM d, yyyy').format(d);
      case 1:
        final (s, e) = _periodRange();
        final end = e.subtract(const Duration(days: 1));
        final endFmt = end.year == s.year ? 'MMM d' : 'MMM d, yyyy';
        return '${DateFormat('MMM d').format(s)} – ${DateFormat(endFmt).format(end)}';
      case 2:
        return DateFormat('MMMM yyyy').format(d);
      default:
        return DateFormat('yyyy').format(d);
    }
  }

  // ───────────────────────── Navigation ─────────────────────────

  bool get _canNavigateForward {
    final now = DateTime.now();
    switch (_selectedTab) {
      case 0: // Day
        final s = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        final today = DateTime(now.year, now.month, now.day);
        return s.isBefore(today);
      case 1: // Week
        final (_, e) = _periodRange();
        return e.isBefore(now);
      case 2: // Month
        return _selectedDate.year < now.year ||
            (_selectedDate.year == now.year && _selectedDate.month < now.month);
      default: // Year
        return _selectedDate.year < now.year;
    }
  }

  void _navigateDate(int delta) {
    HapticFeedback.lightImpact();
    final c = _selectedDate;
    final now = DateTime.now();
    DateTime next;
    switch (_selectedTab) {
      case 0: // Day
        next = DateTime(c.year, c.month, c.day + delta);
        break;
      case 1: // Week
        next = DateTime(c.year, c.month, c.day + (7 * delta));
        break;
      case 2: // Month
        final target = DateTime(c.year, c.month + delta, 1);
        final maxDays = DateTime(target.year, target.month + 1, 0).day;
        next = DateTime(target.year, target.month, math.min(c.day, maxDays));
        break;
      default: // Year
        final target = DateTime(c.year + delta, c.month, 1);
        final maxDays = DateTime(target.year, target.month + 1, 0).day;
        next = DateTime(target.year, target.month, math.min(c.day, maxDays));
    }
    if (next.isAfter(now)) next = now;
    setState(() => _selectedDate = next);
    _computeData();
    HapticFeedback.mediumImpact();
  }

  void _selectTab(int i) {
    _stopAutoCycle();
    HapticFeedback.lightImpact();
    setState(() {
      _selectedTab = i;
      final now = DateTime.now();
      if (_selectedDate.isAfter(now)) {
        _selectedDate = now;
      }
    });
    _computeData();
    HapticFeedback.mediumImpact();
  }

  void _selectType(int i) {
    _stopAutoCycle();
    HapticFeedback.lightImpact();
    setState(() => _type = i == 0 ? 'Expense' : 'Income');
    _computeData();
    HapticFeedback.mediumImpact();
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
        await _pickDate(
          title: 'Select day',
          mode: CupertinoDatePickerMode.date,
        );
        break;
      case 1:
        await _pickWeek();
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

  /// A proper week chooser: scroll through "Oct 19 – Oct 25" style ranges.
  Future<void> _pickWeek() {
    final now = DateTime.now();
    final curStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final (selStart, _) = _periodRange();
    final count = (curStart.difference(DateTime(2020, 1, 1)).inDays ~/ 7) + 1;
    int index = (curStart.difference(selStart).inDays / 7).round().clamp(
      0,
      count - 1,
    );

    DateTime weekStart(int i) =>
        DateTime(curStart.year, curStart.month, curStart.day - 7 * i);

    String label(int i) {
      final s = weekStart(i);
      final e = DateTime(s.year, s.month, s.day + 6);
      final endFmt = e.year == now.year ? 'MMM d' : 'MMM d, yyyy';
      return '${DateFormat('MMM d').format(s)} – ${DateFormat(endFmt).format(e)}';
    }

    return _showPickerSheet(
      title: 'Select week',
      onDone: () {
        setState(() => _selectedDate = index == 0 ? now : weekStart(index));
        _computeData();
      },
      picker: Builder(
        builder: (context) => CupertinoPicker.builder(
          scrollController: FixedExtentScrollController(initialItem: index),
          itemExtent: 46,
          childCount: count,
          onSelectedItemChanged: (i) => index = i,
          itemBuilder: (context, i) {
            final tag = i == 0 ? 'This week' : (i == 1 ? 'Last week' : null);
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label(i),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  if (tag != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
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
          itemExtent: 46,
          onSelectedItemChanged: (index) => selectedYear = currentYear - index,
          children: List.generate(currentYear - 2020 + 1, (index) {
            return Center(
              child: Text(
                (currentYear - index).toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
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
        final bottom = MediaQuery.of(context).padding.bottom;
        final textColor = AppColors.textPrimaryOf(context);

        return CupertinoTheme(
          data: CupertinoThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            primaryColor: AppColors.primary,
            textTheme: CupertinoTextThemeData(
              dateTimePickerTextStyle: TextStyle(
                color: textColor,
                fontSize: 20,
              ),
              pickerTextStyle: TextStyle(color: textColor, fontSize: 20),
            ),
          ),
          // The popup has no Material ancestor, so plain Text widgets get
          // Flutter's yellow double underline. Material supplies a proper
          // default text style and removes it.
          child: Material(
            color: AppColors.cardOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 330 + bottom,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: textColor,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            onDone();
                            Navigator.pop(context);
                          },
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
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
                  Expanded(child: picker),
                  SizedBox(height: bottom),
                ],
              ),
            ),
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
    final screenW = mq.size.width;
    final topPadding = mq.padding.top;
    final double s = (screenW / 390.0).clamp(0.85, 1.25);
    final isDark = AppColors.isDark(context);
    final topHeaderColor = isDark
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

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _stopAutoCycle();
          if (_selectedBucket != null) {
            setState(() => _selectedBucket = null);
          }
          if (_touchedPieIndex != -1) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastSliceTapTime > 250) {
              HapticFeedback.selectionClick();
              setState(() => _touchedPieIndex = -1);
            }
          }
        },
        child: Stack(
          children: [
            // Dynamic overscroll header backdrop: ONLY visible when pulling down past top
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
                  final overscroll = offset < 0 ? -offset : 0.0;
                  if (overscroll <= 0) return const SizedBox.shrink();
                  return Container(
                    height: topPadding + overscroll + 40,
                    color: topHeaderColor,
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
                // Pull-to-refresh matching HomeScreen
                BuddyRefreshControl(
                  onRefresh: refreshData,
                  backgroundColor: topHeaderColor,
                  topPadding: topPadding,
                ),

                // Seamless curved hero header extending full to top with categories donut
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: _buildHeroHeader(isDark, topPadding, s),
                  ),
                ),

                // Main body content below header: takes FULL WIDTH matching the hero header
                SliverToBoxAdapter(
                  child: hasData
                      ? _buildFullWidthBottomSection(isDark, s, mq.padding.bottom)
                      : Padding(
                          padding: EdgeInsets.fromLTRB(
                            0,
                            (24 * s).clamp(16.0, 32.0),
                            0,
                            mq.padding.bottom + kBottomNavigationBarHeight + 60,
                          ),
                          child: _buildEmptyState(),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Top Curved Hero Header ─────────────────────────

  Widget _buildHeroHeader(bool isDark, double topPadding, double s) {
    final double headerBtnSize = (44 * s).clamp(40.0, 48.0);
    final cats = _cachedTopCategories;
    final total = _cachedTotal;
    final accent = _type == 'Expense' ? AppColors.expense : AppColors.income;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [
                  Color(0xFF0F2624), // Deep spruce/emerald
                  Color(0xFF163E3B), // Signature deep teal
                  Color(0xFF1E5D57), // Teal glow
                ]
              : const [
                  Color(0xFF0F3632), // Signature dark emerald
                  Color(0xFF1E5D57), // Signature primary teal
                  Color(0xFF2C7A72), // Radiant teal highlight
                ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular((32 * s).clamp(26.0, 38.0)),
          bottomRight: Radius.circular((32 * s).clamp(26.0, 38.0)),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F3632).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          (20 * s).clamp(16.0, 24.0),
          topPadding + (10 * s).clamp(6.0, 14.0),
          (20 * s).clamp(16.0, 24.0),
          (20 * s).clamp(16.0, 24.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Top Bar: "Statistics" title + Export button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Statistics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (26 * s).clamp(22.0, 28.0),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                GestureDetector(
                  onTap: _isDownloading ? null : _downloadCurrentView,
                  child: Container(
                    width: headerBtnSize,
                    height: headerBtnSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isDownloading
                          ? const BuddyLoadingIndicator(size: 16)
                          : Icon(
                              Icons.ios_share_rounded,
                              color: Colors.white,
                              size: (20 * s).clamp(18.0, 22.0),
                            ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: (12 * s).clamp(10.0, 16.0)),

            // 2. Segmented switch [Expense | Income]
            _buildTypeSwitch(s),
            SizedBox(height: (10 * s).clamp(8.0, 14.0)),

            // 3. "make the day month week after expense income": Period Selector [Day | Week | Month | Year]
            _buildPeriodSwitch(s, accent),
            SizedBox(height: (10 * s).clamp(8.0, 14.0)),

            // 4. "and then the month selector": Date Navigator capsule < [📅 Oct 2026 ▾] >
            _buildHeaderDateNavigator(s, accent),
            SizedBox(height: (12 * s).clamp(10.0, 16.0)),

            // 5. Dual-View Mode Switcher Capsule [⭕ Chart | 📅 Calendar] & Swipable Views
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                _stopAutoCycle();
                _heroDragAccumX = 0;
                _heroDragStartPage = (_heroVisualPageController.hasClients &&
                        _heroVisualPageController.positions.length == 1 &&
                        _heroVisualPageController.position.haveDimensions)
                    ? (_heroVisualPageController.page ??
                        (_kHeroVisualLoopBase + _heroVisualIndex).toDouble())
                    : (_kHeroVisualLoopBase + _heroVisualIndex).toDouble();
                _lastHeroHapticIndex =
                    (_heroDragStartPage.round() % 2 + 2) % 2;
                HapticFeedback.lightImpact();
              },
              onHorizontalDragUpdate: (details) {
                _heroDragAccumX += details.delta.dx;
                final double w = (_heroVisualPageController.hasClients &&
                        _heroVisualPageController.positions.length == 1 &&
                        _heroVisualPageController.position.haveDimensions)
                    ? _heroVisualPageController.position.viewportDimension
                    : MediaQuery.of(context).size.width;
                final double deltaPages =
                    _heroDragAccumX / (w > 0 ? w : 300.0);
                final double newPage = _heroDragStartPage + deltaPages;
                if (_heroVisualPageController.hasClients &&
                    _heroVisualPageController.positions.length == 1 &&
                    _heroVisualPageController.position.haveDimensions) {
                  _heroVisualPageController.position.jumpTo(newPage * w);
                }
                final int nearest = (newPage.round() % 2 + 2) % 2;
                if (nearest != _lastHeroHapticIndex) {
                  _lastHeroHapticIndex = nearest;
                  HapticFeedback.lightImpact();
                }
              },
              onHorizontalDragEnd: (details) {
                final double velocity = details.primaryVelocity ?? 0;
                final double currentP = (_heroVisualPageController.hasClients &&
                        _heroVisualPageController.positions.length == 1 &&
                        _heroVisualPageController.position.haveDimensions)
                    ? (_heroVisualPageController.page ??
                        (_kHeroVisualLoopBase + _heroVisualIndex).toDouble())
                    : (_kHeroVisualLoopBase + _heroVisualIndex).toDouble();
                int target = currentP.round();
                if (velocity > 250) {
                  target = currentP.floor() + 1;
                } else if (velocity < -250) {
                  target = currentP.ceil() - 1;
                }
                _onToggleVisualModeIndex(target);
              },
              onHorizontalDragCancel: () {
                final double currentP = (_heroVisualPageController.hasClients &&
                        _heroVisualPageController.positions.length == 1 &&
                        _heroVisualPageController.position.haveDimensions)
                    ? (_heroVisualPageController.page ??
                        (_kHeroVisualLoopBase + _heroVisualIndex).toDouble())
                    : (_kHeroVisualLoopBase + _heroVisualIndex).toDouble();
                _onToggleVisualModeIndex(currentP.round());
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildVisualModeSelector(s),
                  SizedBox(height: (8 * s).clamp(6.0, 12.0)),
                  SizedBox(
                    height: (295 * s).clamp(275.0, 325.0),
                    child: PageView.builder(
                      controller: _heroVisualPageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (idx) {
                        final mode = (idx % 2 + 2) % 2;
                        if (_heroVisualIndex != mode) {
                          setState(() => _heroVisualIndex = mode);
                        }
                      },
                      itemBuilder: (context, idx) {
                        final mode = (idx % 2 + 2) % 2;
                        if (mode == 0) {
                          return _buildHeaderCategoriesDonut(cats, total, s);
                        } else {
                          return _buildHeaderCalendarView(accent, s);
                        }
                      },
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

  Widget _buildTypeSwitch(double s) {
    final isExpense = _type == 'Expense';
    final height = (38 * s).clamp(34.0, 42.0);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(3.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final segWidth = totalWidth / 2;
          final double leftOffset = isExpense ? 0 : segWidth;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: leftOffset,
                top: 0,
                bottom: 0,
                width: segWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: isExpense
                        ? AppColors.expense.withValues(alpha: 0.38)
                        : const Color(0xFF10B981).withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isExpense
                          ? AppColors.expense.withValues(alpha: 0.60)
                          : const Color(0xFF10B981).withValues(alpha: 0.60),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isExpense
                                    ? AppColors.expense
                                    : const Color(0xFF10B981))
                                .withValues(alpha: 0.25),
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
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _stopAutoCycle();
                        if (!isExpense) {
                          HapticFeedback.lightImpact();
                          _selectType(0);
                        }
                      },
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.south_west_rounded,
                              size: 14,
                              color: isExpense ? Colors.white : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Expense',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isExpense
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isExpense
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _stopAutoCycle();
                        if (isExpense) {
                          HapticFeedback.lightImpact();
                          _selectType(1);
                        }
                      },
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.north_east_rounded,
                              size: 14,
                              color: !isExpense ? Colors.white : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Income',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: !isExpense
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: !isExpense
                                    ? Colors.white
                                    : Colors.white70,
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
          );
        },
      ),
    );
  }

  Widget _buildPeriodSwitch(double s, Color accent) {
    final height = (36 * s).clamp(32.0, 40.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(3.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final segWidth = totalWidth / 4;
          final double leftOffset = _selectedTab * segWidth;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: leftOffset,
                top: 0,
                bottom: 0,
                width: segWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.40),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: List.generate(4, (i) {
                  final isSelected = _selectedTab == i;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _stopAutoCycle();
                        if (!isSelected) {
                          HapticFeedback.lightImpact();
                          _selectTab(i);
                        }
                      },
                      child: Center(
                        child: Text(
                          _tabs[i],
                          style: TextStyle(
                            fontSize: (12.0 * s).clamp(11.0, 13.5),
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.white70,
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
    );
  }

  Widget _buildHeaderDateNavigator(double s, Color accent) {
    final height = (36 * s).clamp(32.0, 40.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _stopAutoCycle();
              _navigateDate(-1);
            },
            child: SizedBox(
              width: 44,
              height: height,
              child: const Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _stopAutoCycle();
                _showDatePicker();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _getDateRangeLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (13.0 * s).clamp(11.5, 14.5),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 17,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _canNavigateForward
                ? () {
                    _stopAutoCycle();
                    _navigateDate(1);
                  }
                : null,
            child: SizedBox(
              width: 44,
              height: height,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: _canNavigateForward ? Colors.white : Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onToggleVisualModeIndex(int targetIndex, {bool isUserAction = true}) {
    if (isUserAction) {
      _stopAutoCycle();
    }
    final int mode = (targetIndex % 2 + 2) % 2;
    if (_heroVisualIndex != mode) {
      if (isUserAction) {
        HapticFeedback.lightImpact();
      }
      setState(() => _heroVisualIndex = mode);
    }
    if (_heroVisualPageController.hasClients &&
        _heroVisualPageController.positions.length == 1 &&
        _heroVisualPageController.position.haveDimensions) {
      _heroVisualPageController.animateToPage(
        targetIndex,
        duration: Duration(milliseconds: isUserAction ? 320 : 450),
        curve: Curves.easeOutCubic,
      ).then((_) {
        if (mounted && isUserAction) {
          HapticFeedback.mediumImpact();
        }
      });
    }
  }

  void _onToggleVisualMode(int mode, {bool isUserAction = true}) {
    final double currentP = (_heroVisualPageController.hasClients &&
            _heroVisualPageController.positions.length == 1 &&
            _heroVisualPageController.position.haveDimensions)
        ? (_heroVisualPageController.page ??
            (_kHeroVisualLoopBase + _heroVisualIndex).toDouble())
        : (_kHeroVisualLoopBase + _heroVisualIndex).toDouble();
    final int current = currentP.round();
    final int currentMode = (current % 2 + 2) % 2;
    if (currentMode == mode) return;
    int diff = mode - currentMode;
    _onToggleVisualModeIndex(current + diff, isUserAction: isUserAction);
  }

  Widget _buildVisualModeSelector(double s) {
    return AnimatedBuilder(
      animation: _heroVisualPageController,
      builder: (context, _) {
        final double currentP = (_heroVisualPageController.hasClients &&
                _heroVisualPageController.positions.length == 1 &&
                _heroVisualPageController.position.haveDimensions)
            ? (_heroVisualPageController.page ??
                (_kHeroVisualLoopBase + _heroVisualIndex).toDouble())
            : (_kHeroVisualLoopBase + _heroVisualIndex).toDouble();
        final int activeMode = (currentP.round() % 2 + 2) % 2;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _visualTabItem(0, Icons.pie_chart_rounded, 'Chart', s, activeMode == 0),
              const SizedBox(width: 4),
              _visualTabItem(1, Icons.calendar_month_rounded, 'Calendar', s, activeMode == 1),
            ],
          ),
        );
      },
    );
  }

  Widget _visualTabItem(
    int index,
    IconData icon,
    String label,
    double s,
    bool isSelected,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onToggleVisualMode(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: (14 * s).clamp(11.0, 18.0),
          vertical: (5 * s).clamp(4.0, 7.0),
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.24)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: isSelected
              ? Border.all(color: Colors.white.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: (11.5 * s).clamp(10.5, 13.0),
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCategoriesDonut(
    List<Map<String, dynamic>> cats,
    double total,
    double s,
  ) {
    if (cats.isEmpty || total <= 0) {
      return _buildHeaderEmptyState(s);
    }

    // Keep ring clean: top 5 categories + "Others"
    final hasOthers = cats.length > 6;
    final shown = hasOthers ? cats.sublist(0, 5) : cats;
    final othersAmt = hasOthers
        ? cats
              .sublist(5)
              .fold<double>(0.0, (sum, c) => sum + (c['amount'] as double))
        : 0.0;

    final slices = <({String name, double amount, Color color})>[
      for (final c in shown)
        (
          name: c['category'] as String,
          amount: c['amount'] as double,
          color: AppColors.getCategoryColor(c['category'] as String),
        ),
      if (hasOthers)
        (name: 'Others', amount: othersAmt, color: const Color(0xFF90A4AE)),
    ];

    final hasTouch = _touchedPieIndex >= 0 && _touchedPieIndex < slices.length;
    final t = hasTouch ? slices[_touchedPieIndex] : null;

    final centerTitle =
        t?.name ?? (_type == 'Expense' ? 'Total spent' : 'Total earned');
    final centerValue = _money(t?.amount ?? total);
    final centerColor = t?.color ?? Colors.white;
    final centerSub = t != null
        ? '${(t.amount / total * 100).toStringAsFixed(1)}% of total'
        : '${cats.length} ${cats.length == 1 ? 'category' : 'categories'}';

    final prev = _cachedPrevTotal;
    final hasPrev = prev > 0;
    final deltaPct = hasPrev ? (total - prev) / prev * 100 : 0.0;
    final isUp = deltaPct >= 0;
    final isExpense = _type == 'Expense';
    final good = isExpense ? !isUp : isUp;
    final badgeColor = good ? const Color(0xFF69F0AE) : const Color(0xFFFF8A80);
    const compareNames = ['yesterday', 'last week', 'last month', 'last year'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: (200 * s).clamp(180.0, 220.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 3,
                  centerSpaceRadius: (68 * s).clamp(60.0, 76.0),
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      if (!event.isInterestedForInteractions) return;
                      if (event is FlTapDownEvent || event is FlTapUpEvent) {
                        _stopAutoCycle();
                        final section = pieTouchResponse?.touchedSection;
                        final i = section?.touchedSectionIndex ?? -1;
                        if (i >= 0 && i < slices.length) {
                          _lastSliceTapTime =
                              DateTime.now().millisecondsSinceEpoch;
                          HapticFeedback.selectionClick();
                          setState(() {
                            _touchedPieIndex = (_touchedPieIndex == i) ? -1 : i;
                          });
                        } else if (_touchedPieIndex != -1) {
                          _lastSliceTapTime =
                              DateTime.now().millisecondsSinceEpoch;
                          HapticFeedback.selectionClick();
                          setState(() => _touchedPieIndex = -1);
                        }
                      }
                    },
                  ),
                  sections: List.generate(slices.length, (i) {
                    final sItem = slices[i];
                    final selected = i == _touchedPieIndex;
                    final dim = hasTouch && !selected;
                    return PieChartSectionData(
                      value: sItem.amount,
                      showTitle: false,
                      radius: selected ? 22 : 15,
                      color: dim
                          ? sItem.color.withValues(alpha: 0.28)
                          : sItem.color,
                    );
                  }),
                ),
                swapAnimationDuration: const Duration(milliseconds: 350),
                swapAnimationCurve: Curves.easeOutCubic,
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _stopAutoCycle();
                  if (hasTouch) {
                    _lastSliceTapTime = DateTime.now().millisecondsSinceEpoch;
                    HapticFeedback.selectionClick();
                    setState(() => _touchedPieIndex = -1);
                  }
                },
                child: SizedBox(
                  width: (126 * s).clamp(110.0, 136.0),
                  height: (126 * s).clamp(110.0, 136.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        centerTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          centerValue,
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            color: centerColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        centerSub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: (8 * s).clamp(6.0, 12.0)),
        // Footer pill: reset if slice selected, or comparison / tap hint
        if (hasTouch)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _stopAutoCycle();
              HapticFeedback.selectionClick();
              setState(() => _touchedPieIndex = -1);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Reset: ${t?.name ?? ''}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (hasPrev)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUp ? Icons.north_east_rounded : Icons.south_east_rounded,
                  size: 12,
                  color: badgeColor,
                ),
                const SizedBox(width: 5),
                Text(
                  '${deltaPct.abs().toStringAsFixed(1)}% vs ${compareNames[_selectedTab]}',
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.0,
              ),
            ),
            child: Text(
              'Tap a slice to filter',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  // ───────────────────────── Calendar View for Hero ─────────────────────────

  Widget _buildHeaderCalendarView(Color accent, double s) {
    if (_cachedTotal <= 0 && _cachedTxns.isEmpty) {
      return _buildHeaderEmptyState(s);
    }

    if (_selectedTab == 0) {
      return _buildHeaderDayTimeline(accent, s);
    }

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: _buildHeaderCalendarGrid(_cachedPoints, accent, s),
      ),
    );
  }

  Widget _buildHeaderCalendarGrid(List<double> points, Color accent, double s) {
    final maxVal = points.isEmpty ? 0.0 : points.reduce(math.max);
    final now = DateTime.now();

    Widget cell(int i, String label, {String? sub, double height = 36}) {
      final val = i < points.length ? points[i] : 0.0;
      final intensity = (maxVal > 0 && val > 0)
          ? (val / maxVal).clamp(0.2, 1.0).toDouble()
          : 0.0;
      final future = _bucketStart(i).isAfter(now);
      final selected = _selectedBucket == i;
      final today = _isCurrentBucket(i, now);

      return Padding(
        padding: const EdgeInsets.all(2.0),
        child: GestureDetector(
          onTap: future
              ? null
              : () {
                  _stopAutoCycle();
                  HapticFeedback.selectionClick();
                  setState(() => _selectedBucket = i);
                  final txns = _txnsForBucket(i);
                  _showTransactionsSheet(
                    title: _bucketLabel(i),
                    subtitle: txns.isNotEmpty
                        ? '${txns.length} ${txns.length == 1 ? 'transaction' : 'transactions'}'
                        : 'No ${_type.toLowerCase()} transactions',
                    txns: txns,
                    color: accent,
                    icon: Icons.event_note_rounded,
                    showCategory: true,
                  );
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: height,
            decoration: BoxDecoration(
              color: intensity > 0
                  ? accent.withValues(
                      alpha: (0.35 + intensity * 0.55).clamp(0.35, 0.95),
                    )
                  : Colors.white.withValues(alpha: future ? 0.05 : 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? Colors.white
                    : (today
                          ? Colors.white.withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.08)),
                width: selected ? 2.0 : (today ? 1.5 : 1.0),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 1.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: sub != null
                              ? (11.0 * s).clamp(10.0, 12.5)
                              : (12.0 * s).clamp(11.0, 13.5),
                          fontWeight: (intensity > 0.5 || today || selected)
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (sub != null)
                        Text(
                          sub,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: sub != '–'
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: sub != '–'
                                ? Colors.white.withValues(alpha: 0.95)
                                : Colors.white.withValues(alpha: 0.40),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
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
      case 1: // Week: 7 days
        content = grid(7, [
          for (var i = 0; i < 7; i++)
            cell(
              i,
              _cachedLabels[i],
              sub: points[i] > 0 ? _compact(points[i]) : '–',
              height: (58 * s).clamp(52.0, 68.0),
            ),
        ]);
        break;
      case 3: // Year: 12 months
        content = grid(4, [
          for (var i = 0; i < 12; i++)
            cell(
              i,
              _cachedLabels[i],
              sub: points[i] > 0 ? _compact(points[i]) : '–',
              height: (48 * s).clamp(42.0, 56.0),
            ),
        ]);
        break;
      default: // Month: real calendar aligned to weekdays
        final lead =
            DateTime(_selectedDate.year, _selectedDate.month, 1).weekday - 1;
        content = Column(
          children: [
            Row(
              children: [
                for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            grid(7, [
              for (var i = 0; i < lead; i++) null,
              for (var i = 0; i < points.length; i++)
                cell(
                  i,
                  '${i + 1}',
                  sub: points[i] > 0 ? _compact(points[i]) : '–',
                  height: (38 * s).clamp(34.0, 44.0),
                ),
            ]),
          ],
        );
    }

    return content;
  }

  Widget _buildHeaderDayTimeline(Color accent, double s) {
    final txns = _cachedTxns;
    if (txns.isEmpty) {
      return const Center(
        child: Text(
          'No transactions recorded for today',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final sign = _type == 'Expense' ? '-' : '+';
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: txns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final t = txns[i];
        final dt = DateTime.tryParse(t['date'] as String);
        final time = dt != null ? DateFormat('h:mm a').format(dt) : '';
        final cat = (t['category'] as String?)?.trim() ?? 'Other';
        final note = (t['note'] as String?)?.trim() ?? '';
        final color = AppColors.getCategoryColor(cat);
        final amt = (t['amount'] as num).toDouble();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _stopAutoCycle();
            HapticFeedback.lightImpact();
            final displayMap = {
              'id': t['id'],
              'title': note.isNotEmpty ? note : cat,
              'amount': amt,
              'category': cat,
              'date': t['date'],
              'type': _type,
              'icon': t['icon'],
              'note': note,
            };
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TransactionDetailScreen(data: displayMap),
              ),
            ).then((_) => refreshData());
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    IconHelper.getIcon(t['icon']),
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.isNotEmpty ? note : cat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '$time • $cat',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$sign${FormatUtils.formatCurrencyFull(amt)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderEmptyState(double s) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: (20 * s).clamp(16.0, 26.0)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: (60 * s).clamp(52.0, 68.0),
              height: (60 * s).clamp(52.0, 68.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1.2,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.donut_large_rounded,
                  size: 28,
                  color: Colors.white60,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No ${_type.toLowerCase()} transactions',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Nothing recorded for ${_getDateRangeLabel()}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration([double radius = 22]) {
    final isDark = AppColors.isDark(context);
    return BoxDecoration(
      color: isDark ? const Color(0xFF102624) : AppColors.cardOf(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark
            ? const Color(0xFF1E5D57).withValues(alpha: 0.45)
            : AppColors.borderOf(context),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.30)
              : const Color(0xFF0F3632).withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
        if (!isDark)
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
      ],
    );
  }

  // ───────────────────────── Full-Width Bottom Section ─────────────────────────

  Widget _buildFullWidthBottomSection(
    bool isDark,
    double s,
    double bottomPadding,
  ) {
    final cats = _cachedTopCategories;
    final total = _cachedTotal;
    final hasTouch = _touchedPieIndex >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: (16 * s).clamp(12.0, 18.0)),

        // 1. Daily Avg & Peak in the SAME ROW, full width split between them with curves
        _buildInsightTiles(s, isDark),

        SizedBox(height: (16 * s).clamp(12.0, 20.0)),

        // 2. Category Breakdown portion ALSO full width with matching curves
        Container(
          margin: EdgeInsets.symmetric(
            horizontal: (16 * s).clamp(14.0, 20.0),
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF102624) : AppColors.cardOf(context),
            borderRadius: BorderRadius.circular((22 * s).clamp(18.0, 24.0)),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF1E5D57).withValues(alpha: 0.45)
                  : AppColors.borderOf(context),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.30)
                    : const Color(0xFF0F172A).withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              if (!isDark)
                BoxShadow(
                  color: const Color(0xFF0F3632).withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  (18 * s).clamp(14.0, 22.0),
                  (16 * s).clamp(14.0, 20.0),
                  (18 * s).clamp(14.0, 22.0),
                  (12 * s).clamp(10.0, 14.0),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C7A72)
                            : const Color(0xFF0F766E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Category Breakdown',
                        style: TextStyle(
                          fontSize: (16.5 * s).clamp(15.0, 18.0),
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (hasTouch)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _touchedPieIndex = -1);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : const Color(0xFF0F766E).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : const Color(0xFF0F766E).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: isDark
                                    ? AppColors.primary
                                    : const Color(0xFF0F766E),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Reset',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? AppColors.primary
                                      : const Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFEEF6F5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.14)
                                : const Color(0xFF0F766E).withValues(alpha: 0.25),
                            width: 0.9,
                          ),
                        ),
                        child: Text(
                          '${cats.length} ${cats.length == 1 ? 'category' : 'categories'}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF0F766E),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 0.8,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE2E8F0),
              ),
              for (var i = 0; i < cats.length; i++) ...[
                _categoryRow(i, cats[i], total, isDark, s),
                if (i != cats.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.6,
                    indent: (64 * s).clamp(56.0, 72.0),
                    endIndent: (18 * s).clamp(14.0, 22.0),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE2E8F0),
                  ),
              ],
            ],
          ),
        ),

        SizedBox(height: bottomPadding + kBottomNavigationBarHeight + 50),
      ],
    );
  }

  // ───────────────────────── Daily Avg & Peak (Same Row, Full Width with Curves) ─────────────────────────

  Widget _buildInsightTiles(double s, bool isDark) {
    final points = _cachedPoints;
    final total = _cachedTotal;
    final txns = _cachedTxns;
    final isDay = _selectedTab == 0;

    // Peak bucket
    final peakVal = points.isEmpty ? 0.0 : points.reduce(math.max);
    final peakIdx = points.indexOf(peakVal);
    String peakLabel = 'None';
    if (peakIdx >= 0 && peakVal > 0) {
      if (_selectedTab == 0) {
        peakLabel = DateFormat('h a').format(_bucketStart(peakIdx));
      } else if (_selectedTab == 2) {
        peakLabel = DateFormat('MMM d').format(_bucketStart(peakIdx));
      } else {
        peakLabel = _cachedLabels[peakIdx];
      }
    }

    final double avg;
    final String avgLabel;
    final String avgSub;
    if (isDay) {
      avg = txns.isEmpty ? 0.0 : total / txns.length;
      avgLabel = 'Avg / Txn';
      avgSub = '${txns.length} ${txns.length == 1 ? 'txn' : 'txns'} today';
    } else if (_selectedTab == 3) {
      final elapsed = _elapsedBuckets(points.length);
      avg = total / elapsed;
      avgLabel = 'Monthly Avg';
      avgSub = '$elapsed active ${elapsed == 1 ? 'mo' : 'mos'}';
    } else {
      final elapsed = _elapsedBuckets(points.length);
      avg = total / elapsed;
      avgLabel = 'Daily Avg';
      avgSub = '$elapsed active ${elapsed == 1 ? 'day' : 'days'}';
    }

    final avgColor = isDark ? const Color(0xFF4DD0E1) : const Color(0xFF0F766E);
    final peakColor = _type == 'Expense'
        ? (isDark ? const Color(0xFFFF7043) : const Color(0xFFEA580C))
        : (isDark ? const Color(0xFF10B981) : const Color(0xFF059669));

    final peakTitle = _type == 'Expense' ? 'Peak Spend' : 'Peak Income';
    final peakSub = peakVal > 0 ? 'Peak · $peakLabel' : 'No activity';
    final peakTxns = peakIdx >= 0 ? _txnsForBucket(peakIdx) : <Map<String, dynamic>>[];
    final avgTxns = _cachedTxns;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: (16 * s).clamp(14.0, 20.0),
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF102624) : AppColors.cardOf(context),
        borderRadius: BorderRadius.circular((22 * s).clamp(18.0, 24.0)),
        border: Border.all(
          color: isDark
              ? const Color(0xFF1E5D57).withValues(alpha: 0.45)
              : AppColors.borderOf(context),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.30)
                : const Color(0xFF0F172A).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F3632).withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left half: Daily Average
            Expanded(
              child: _splitInsightHalf(
                icon: Icons.analytics_rounded,
                color: avgColor,
                label: avgLabel,
                subtitle: avgSub,
                value: _money(avg),
                isDark: isDark,
                s: s,
                onTap: avgTxns.isEmpty
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _showTransactionsSheet(
                          title: avgLabel,
                          subtitle:
                              '${avgTxns.length} ${avgTxns.length == 1 ? 'transaction' : 'transactions'} • Total ${_money(total)}',
                          txns: avgTxns,
                          color: avgColor,
                          icon: Icons.analytics_rounded,
                          showCategory: true,
                        );
                      },
              ),
            ),

            // Clean vertical divider split
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: isDark
                  ? const Color(0xFF1E5D57).withValues(alpha: 0.35)
                  : const Color(0xFFCBD5E1),
            ),

            // Right half: Peak
            Expanded(
              child: _splitInsightHalf(
                icon: Icons.local_fire_department_rounded,
                color: peakColor,
                label: peakTitle,
                subtitle: peakSub,
                value: _money(peakVal),
                isDark: isDark,
                s: s,
                onTap: peakTxns.isEmpty
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _showTransactionsSheet(
                          title: '$peakTitle ($peakLabel)',
                          subtitle:
                              '${peakTxns.length} ${peakTxns.length == 1 ? 'transaction' : 'transactions'}',
                          txns: peakTxns,
                          color: peakColor,
                          icon: Icons.local_fire_department_rounded,
                          showCategory: true,
                        );
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _splitInsightHalf({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required String value,
    required bool isDark,
    required double s,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: (14 * s).clamp(12.0, 18.0),
            vertical: (13 * s).clamp(11.0, 16.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: (32 * s).clamp(28.0, 36.0),
                    height: (32 * s).clamp(28.0, 36.0),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.22 : 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: color.withValues(alpha: isDark ? 0.38 : 0.32),
                        width: 1.1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: (17 * s).clamp(15.0, 19.0),
                        color: color,
                      ),
                    ),
                  ),
                  SizedBox(width: (8 * s).clamp(6.0, 10.0)),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: (12.0 * s).clamp(11.0, 13.5),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.75)
                            : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: (8 * s).clamp(6.0, 10.0)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: (18.0 * s).clamp(16.0, 20.0),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark
                        ? Colors.white
                        : const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: (11.0 * s).clamp(10.0, 12.0),
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.60)
                      : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Categories Ledger Row ─────────────────────────

  Widget _categoryRow(
    int idx,
    Map<String, dynamic> cat,
    double total,
    bool isDark,
    double s,
  ) {
    final name = cat['category'] as String;
    final amt = cat['amount'] as double;
    final count = (cat['count'] as int?) ?? 1;
    final pct = total > 0 ? amt / total * 100 : 0.0;
    final color = AppColors.getCategoryColor(name);
    final hasOthers = _cachedTopCategories.length > 6;
    final limit = hasOthers ? 5 : _cachedTopCategories.length;
    final highlighted =
        (idx == _touchedPieIndex && idx < limit) ||
        (hasOthers && _touchedPieIndex == limit && idx >= limit);

    return Material(
      color: highlighted
          ? color.withValues(alpha: isDark ? 0.22 : 0.10)
          : Colors.transparent,
      child: InkWell(
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
        child: Container(
          decoration: highlighted
              ? BoxDecoration(
                  border: Border(left: BorderSide(color: color, width: 4)),
                )
              : null,
          padding: EdgeInsets.symmetric(
            horizontal: (18 * s).clamp(14.0, 22.0),
            vertical: (12 * s).clamp(10.0, 14.0),
          ),
          child: Row(
            children: [
              Container(
                width: (40 * s).clamp(36.0, 44.0),
                height: (40 * s).clamp(36.0, 44.0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.35 : 0.30),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Icon(
                    IconHelper.getIcon(cat['icon']),
                    color: color,
                    size: (19 * s).clamp(17.0, 21.0),
                  ),
                ),
              ),
              SizedBox(width: (12 * s).clamp(10.0, 14.0)),
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
                              fontSize: (14.5 * s).clamp(13.5, 16.0),
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        Text(
                          _money(amt),
                          style: TextStyle(
                            fontSize: (14.5 * s).clamp(13.5, 16.0),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (pct / 100.0).clamp(0.0, 1.0),
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 4.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$count ${count == 1 ? 'transaction' : 'transactions'}',
                            style: TextStyle(
                              fontSize: (11.5 * s).clamp(10.5, 12.5),
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white60
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),
                        Text(
                          '${pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: (11.5 * s).clamp(10.5, 12.5),
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF1E293B),
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
    final isDark = AppColors.isDark(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 24),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceOf(context)
                  : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              size: 34,
              color: isDark
                  ? AppColors.textSecondaryOf(context)
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No ${_type == 'Expense' ? 'expenses' : 'income'} here',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? Colors.white
                  : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use the arrows above to look at another period.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark
                  ? Colors.white60
                  : const Color(0xFF64748B),
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
    final isDark = AppColors.isDark(context);
    final totalAmt = txns.fold<double>(
      0.0,
      (sum, r) => sum + (r['amount'] as num).toDouble(),
    );
    final valueColor = _type == 'Income'
        ? AppColors.income
        : (isDark ? Colors.white : const Color(0xFF0F172A));

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
            color: isDark ? const Color(0xFF102624) : AppColors.cardOf(ctx),
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
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.20)
                      : const Color(0xFFCBD5E1),
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
                        color: color.withValues(alpha: isDark ? 0.20 : 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: color.withValues(alpha: isDark ? 0.35 : 0.28),
                          width: 1.0,
                        ),
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
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
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
                              color: isDark
                                  ? Colors.white60
                                  : const Color(0xFF64748B),
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
                thickness: 0.8,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE2E8F0),
              ),
              Flexible(
                child: txns.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No transactions found.',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white60
                                : const Color(0xFF64748B),
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
                          final catColor = AppColors.getCategoryColor(cat);
                          final catIcon = IconHelper.getIcon(item['icon']);

                          final hasNote = note.isNotEmpty;
                          final rowTitle = hasNote ? note : cat;
                          final rowSub = hasNote ? '$cat • $date' : date;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.surfaceOf(context)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF1E5D57).withValues(alpha: 0.3)
                                    : const Color(0xFFE2E8F0),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: isDark ? 0.20 : 0.14),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: catColor.withValues(alpha: isDark ? 0.35 : 0.28),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      catIcon,
                                      size: 19,
                                      color: catColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
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
                                          letterSpacing: -0.2,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        rowSub,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white60
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  FormatUtils.formatCurrencyFull(
                                    (item['amount'] as num).toDouble(),
                                  ),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
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

