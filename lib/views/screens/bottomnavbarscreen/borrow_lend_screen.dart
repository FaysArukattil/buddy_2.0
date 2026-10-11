// lib/views/screens/bottomnavbarscreen/borrow_lend_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/debt.dart';
import '../../../services/debt_service.dart';
import '../../../utils/colors.dart';
import '../../../utils/format_utils.dart';
import '../../../services/Network_services.dart';
import '../../../utils/app_snackbar.dart';

class BorrowLendScreen extends StatefulWidget {
  const BorrowLendScreen({super.key});

  @override
  State<BorrowLendScreen> createState() => BorrowLendScreenState();
}

class BorrowLendScreenState extends State<BorrowLendScreen>
    with AutomaticKeepAliveClientMixin {
  final DebtService _debtService = DebtService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late Stream<List<DebtModel>> _debtsStream;
  List<DebtModel> _cachedDebts = const [];

  int _typeFilter = 0; // 0 = All, 1 = Lent (You Gave), 2 = Borrowed (You Took)
  int _statusFilter = 0; // 0 = Pending, 1 = Settled, 2 = All
  String _searchQuery = '';
  List<String> _recentContacts = [];
  bool _includeDebtsInHome = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _debtsStream = _debtService.getDebtsStream();
    _loadHomeSyncPreference();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHomeSyncPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _includeDebtsInHome = prefs.getBool('include_debts_in_balance') ?? true;
      });
    }
  }

  Future<void> _toggleHomeSyncPreference() async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    final newVal = !_includeDebtsInHome;
    await prefs.setBool('include_debts_in_balance', newVal);
    if (mounted) {
      setState(() => _includeDebtsInHome = newVal);
      AppSnackbar.showInfo(
        context,
        newVal
            ? 'Debts are now reflected in the Home Screen balance'
            : 'Debts are now tracked separately from Home Screen',
      );
    }
  }

  Future<void> refreshData() async {
    _debtsStream = _debtService.getDebtsStream();
    await _loadHomeSyncPreference();
    if (mounted) setState(() {});
  }

  /// Called by the global FAB when on this tab. Pre-selects type based on
  /// current filter tab: Lent filter → opens Lend, Borrowed filter → opens Borrow.
  void openAddSheet() {
    // Map current type filter to initialType for the sheet
    // 0=All → no preference (Lend), 1=Lent → Lend, 2=Borrowed → Borrow
    final initialType = _typeFilter == 2 ? 1 : 0;
    _openAddEditSheet(context, initialType: initialType);
  }

  String _formatAmount(double amount) {
    return FormatUtils.formatCurrency(amount);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: StreamBuilder<List<DebtModel>>(
          stream: _debtsStream,
          initialData: _cachedDebts.isNotEmpty ? _cachedDebts : null,
          builder: (context, snapshot) {
            final allDebts = snapshot.data ?? _cachedDebts;
            if (snapshot.hasData && snapshot.data != null) {
              _cachedDebts = snapshot.data!;
              final contacts = <String>{};
              for (final d in _cachedDebts) {
                if (d.personName.trim().isNotEmpty) {
                  contacts.add(d.personName.trim());
                }
              }
              _recentContacts = contacts.toList();
            }
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData &&
                    _cachedDebts.isEmpty;

            // Compute summary metrics (only pending counts towards active balance)
            double totalLentPending = 0;
            double totalBorrowedPending = 0;
            final dueTodayOrOverdue = <DebtModel>[];

            for (final d in allDebts) {
              if (!d.isRepaid) {
                if (d.isLend) {
                  totalLentPending += d.amount;
                } else {
                  totalBorrowedPending += d.amount;
                }
                if (d.isDueToday || d.isOverdue) {
                  dueTodayOrOverdue.add(d);
                }
              }
            }

            final netBalance = totalLentPending - totalBorrowedPending;

            // Filter debts
            final filteredDebts = allDebts.where((d) {
              if (_typeFilter == 1 && !d.isLend) return false;
              if (_typeFilter == 2 && !d.isBorrow) return false;
              if (_statusFilter == 0 && d.isRepaid) return false;
              if (_statusFilter == 1 && !d.isRepaid) return false;
              if (_searchQuery.isNotEmpty) {
                final query = _searchQuery.toLowerCase();
                final nameMatches =
                    d.personName.toLowerCase().contains(query);
                final noteMatches =
                    d.note?.toLowerCase().contains(query) ?? false;
                if (!nameMatches && !noteMatches) return false;
              }
              return true;
            }).toList();

            // Build header items list for efficient rendering
            final headerWidgets = <Widget>[
              _buildSummaryCards(
                context,
                totalLentPending: totalLentPending,
                totalBorrowedPending: totalBorrowedPending,
                netBalance: netBalance,
              ),
              const SizedBox(height: 14),
              if (dueTodayOrOverdue.isNotEmpty) ...[
                _buildDueAlertBanner(context, dueTodayOrOverdue),
                const SizedBox(height: 14),
              ],
              _buildSearchBar(context),
              const SizedBox(height: 12),
              _buildTypeFilters(context, allDebts),
              const SizedBox(height: 10),
              _buildStatusFilters(context, allDebts),
              const SizedBox(height: 16),
            ];

            final headerCount = headerWidgets.length;
            final debtCount = filteredDebts.length;
            final totalCount = headerCount + (debtCount == 0 ? 1 : debtCount);

            return Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: refreshData,
                          color: AppColors.primary,
                          child: ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: totalCount,
                            itemBuilder: (context, index) {
                              if (index < headerCount) {
                                return headerWidgets[index];
                              }
                              final debtIndex = index - headerCount;
                              if (debtCount == 0) {
                                return _buildEmptyState(context);
                              }
                              return _buildDebtCard(
                                context,
                                filteredDebts[debtIndex],
                                isDark,
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      // No internal FAB — global FAB handles this tab via openAddSheet()
    );
  }

  // ─── HEADER ───
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Borrow & Lend',
                  style: TextStyle(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Track friend dues, debts & repayments',
                  style: TextStyle(
                    color: AppColors.textSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Home Screen Sync Toggle Pill
          GestureDetector(
            onTap: _toggleHomeSyncPreference,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _includeDebtsInHome
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _includeDebtsInHome
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : AppColors.borderOf(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _includeDebtsInHome
                        ? Icons.home_rounded
                        : Icons.home_outlined,
                    size: 14,
                    color: _includeDebtsInHome
                        ? AppColors.primary
                        : AppColors.textSecondaryOf(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _includeDebtsInHome ? 'On Home' : 'Separate',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _includeDebtsInHome
                          ? AppColors.primary
                          : AppColors.textSecondaryOf(context),
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

  // ─── SUMMARY CARDS ───
  Widget _buildSummaryCards(
    BuildContext context, {
    required double totalLentPending,
    required double totalBorrowedPending,
    required double netBalance,
  }) {
    final isDark = AppColors.isDark(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Net Position Banner
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NET BALANCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textLightOf(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${netBalance >= 0 ? '+' : '-'}${_formatAmount(netBalance.abs())}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: netBalance >= 0 ? AppColors.income : AppColors.expense,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (netBalance >= 0 ? AppColors.income : AppColors.expense)
                      .withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (netBalance >= 0 ? AppColors.income : AppColors.expense)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      netBalance >= 0
                          ? Icons.arrow_circle_up_rounded
                          : Icons.arrow_circle_down_rounded,
                      size: 14,
                      color: netBalance >= 0 ? AppColors.income : AppColors.expense,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      netBalance >= 0 ? 'You are owed' : 'You owe',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: netBalance >= 0 ? AppColors.income : AppColors.expense,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: AppColors.borderOf(context).withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),

          // Two clean action pills: Lent (To Receive) & Borrowed (To Pay)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _typeFilter = _typeFilter == 1 ? 0 : 1;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _typeFilter == 1
                          ? AppColors.income.withValues(alpha: isDark ? 0.20 : 0.14)
                          : AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _typeFilter == 1
                            ? AppColors.income
                            : AppColors.borderOf(context).withValues(alpha: 0.4),
                        width: _typeFilter == 1 ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.arrow_upward_rounded, size: 14, color: AppColors.income),
                            const SizedBox(width: 4),
                            Text(
                              'To Receive',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.income,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '+${_formatAmount(totalLentPending)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.income,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pending from friends',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textLightOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _typeFilter = _typeFilter == 2 ? 0 : 2;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _typeFilter == 2
                          ? AppColors.expense.withValues(alpha: isDark ? 0.20 : 0.14)
                          : AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _typeFilter == 2
                            ? AppColors.expense
                            : AppColors.borderOf(context).withValues(alpha: 0.4),
                        width: _typeFilter == 2 ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_downward_rounded, size: 14, color: AppColors.expense),
                          const SizedBox(width: 4),
                          Text(
                            'To Pay',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.expense,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '-${_formatAmount(totalBorrowedPending)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.expense,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pending you owe',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textLightOf(context),
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
  }

  // ─── DUE TODAY / OVERDUE ALERT BANNER ───
  Widget _buildDueAlertBanner(
    BuildContext context,
    List<DebtModel> dues,
  ) {
    final count = dues.length;
    final firstPerson = dues.first.personName;
    final overdueCount = dues.where((d) => d.isOverdue).length;
    final dueTodayCount = dues.where((d) => d.isDueToday).length;

    String subtitle = '';
    if (overdueCount > 0 && dueTodayCount > 0) {
      subtitle = '$dueTodayCount due today, $overdueCount overdue ($firstPerson & others)';
    } else if (overdueCount > 0) {
      subtitle = '$overdueCount overdue repayment(s) need follow-up!';
    } else {
      subtitle = '$dueTodayCount repayment(s) expected today ($firstPerson)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF9800).withValues(alpha: 0.16),
            const Color(0xFFFF5722).withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Color(0xFFF57C00),
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
                    const Text(
                      'Repayment Action Needed',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFFE65100),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── SEARCH BAR ───
  Widget _buildSearchBar(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.textSecondaryOf(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimaryOf(context),
              ),
              decoration: InputDecoration(
                hintText: 'Search by friend name or note...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textLightOf(context),
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              child: Icon(
                Icons.cancel_rounded,
                size: 18,
                color: AppColors.textLightOf(context),
              ),
            ),
        ],
      ),
    );
  }

  // ─── TYPE FILTERS ───
  Widget _buildTypeFilters(BuildContext context, List<DebtModel> allDebts) {
    final lentCount = allDebts.where((d) => d.isLend).length;
    final borrowCount = allDebts.where((d) => d.isBorrow).length;

    final tabs = [
      'All (${allDebts.length})',
      'Lent ($lentCount)',
      'Borrowed ($borrowCount)',
    ];

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(tabs.length, (idx) {
          final isSelected = _typeFilter == idx;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _typeFilter = idx);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    tabs[idx],
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondaryOf(context),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── STATUS FILTERS ───
  Widget _buildStatusFilters(
    BuildContext context,
    List<DebtModel> allDebts,
  ) {
    final pendingCount = allDebts.where((d) => !d.isRepaid).length;
    final settledCount = allDebts.where((d) => d.isRepaid).length;

    Widget buildPill(String label, int count, int index) {
      final isSelected = _statusFilter == index;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _statusFilter = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.borderOf(context).withValues(alpha: 0.5),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        buildPill('Pending', pendingCount, 0),
        const SizedBox(width: 8),
        buildPill('Settled', settledCount, 1),
        const SizedBox(width: 8),
        buildPill('All', allDebts.length, 2),
      ],
    );
  }

  // ─── DEBT CARD ───
  Widget _buildDebtCard(
    BuildContext context,
    DebtModel debt,
    bool isDark,
  ) {
    final isLend = debt.isLend;
    final isRepaid = debt.isRepaid;
    final isOverdue = debt.isOverdue;
    final isDueToday = debt.isDueToday;
    final daysDiff = debt.daysDifference;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isRepaid) {
      if (debt.isRepaidOnTime) {
        statusColor = const Color(0xFF1EBE5D);
        final dateStr = debt.repaidDate != null
            ? DateFormat('dd MMM').format(debt.repaidDate!)
            : '';
        statusText = dateStr.isNotEmpty ? 'Paid on time ($dateStr)' : 'Paid on time';
        statusIcon = Icons.check_circle_rounded;
      } else if (debt.isRepaidLate) {
        statusColor = const Color(0xFFFF9800);
        final dateStr = debt.repaidDate != null
            ? DateFormat('dd MMM').format(debt.repaidDate!)
            : '';
        statusText = 'Paid ${debt.daysLateRepaid}d late${dateStr.isNotEmpty ? " ($dateStr)" : ""}';
        statusIcon = Icons.warning_amber_rounded;
      } else {
        statusColor = AppColors.income;
        statusText = debt.repaidDate != null
            ? 'Settled on ${DateFormat('dd MMM').format(debt.repaidDate!)}'
            : 'Settled';
        statusIcon = Icons.check_circle_rounded;
      }
    } else if (isDueToday) {
      statusColor = const Color(0xFFFF9800);
      statusText = 'Due Today!';
      statusIcon = Icons.alarm_rounded;
    } else if (isOverdue) {
      statusColor = AppColors.expense;
      final daysLate = daysDiff.abs();
      statusText = 'Overdue by $daysLate ${daysLate == 1 ? "day" : "days"}';
      statusIcon = Icons.warning_rounded;
    } else {
      statusColor = const Color(0xFF00897B);
      if (daysDiff == 1) {
        statusText = 'Due tomorrow';
      } else {
        statusText = 'Due in $daysDiff days';
      }
      statusIcon = Icons.schedule_rounded;
    }

    final initials = debt.personName.trim().isNotEmpty
        ? debt.personName
            .trim()
            .split(' ')
            .take(2)
            .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
            .join()
        : 'F';

    final accentStripeColor =
        isRepaid ? const Color(0xFF1EBE5D) : debt.urgencyColor;
    final borderColor = (isDueToday || isOverdue) && !isRepaid
        ? (isDueToday ? const Color(0xFFFF9800) : AppColors.expense)
            .withValues(alpha: 0.5)
        : AppColors.borderOf(context).withValues(alpha: 0.5);
    final borderWidth = (isDueToday || isOverdue) && !isRepaid ? 1.5 : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent stripe indicator
              Container(
                width: 4.5,
                color: accentStripeColor,
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _showDebtDetailModal(context, debt),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                // ── Top Row: Avatar + Name & Subtitle + Amount ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isLend
                                  ? [const Color(0xFF26A69A), const Color(0xFF00897B)]
                                  : [const Color(0xFFFF7043), const Color(0xFFE65100)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        if (!isRepaid)
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: debt.urgencyColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cardOf(context),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),

                    // Name + Subtitle (Takes full middle width safely)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            debt.personName.trim().isNotEmpty
                                ? debt.personName.trim()
                                : (isLend ? 'Friend (Lent)' : 'Friend (Borrowed)'),
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryOf(context),
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isLend
                                ? 'Given on ${DateFormat('dd MMM yyyy').format(debt.date)}'
                                : 'Taken on ${DateFormat('dd MMM yyyy').format(debt.date)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textLightOf(context),
                            ),
                          ),
                          if (debt.note != null &&
                              debt.note!.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              debt.note!.trim(),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondaryOf(context),
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Amount Display
                    Text(
                      isRepaid
                          ? '${isLend ? '+' : '-'}${_formatAmount(debt.originalAmount)}'
                          : '${isLend ? '+' : '-'}${_formatAmount(debt.amount)}',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: isRepaid
                            ? (isDark ? Colors.white70 : AppColors.textSecondary)
                            : (isLend
                                ? AppColors.income
                                : AppColors.expense),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── Badges Row: Type Badge + Urgency Badge + Status Badge ──
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Type Badge (Lent / Borrowed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (isLend ? AppColors.income : AppColors.expense)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLend
                                ? Icons.arrow_outward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 11,
                            color: isLend ? AppColors.income : AppColors.expense,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isLend ? 'Lent' : 'Borrowed',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isLend
                                  ? AppColors.income
                                  : AppColors.expense,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Urgency Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (isRepaid
                                ? const Color(0xFF1EBE5D)
                                : debt.urgencyColor)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isRepaid
                                ? Icons.check_circle_rounded
                                : (debt.isUrgent
                                    ? Icons.priority_high_rounded
                                    : (debt.isLenient
                                        ? Icons.spa_rounded
                                        : Icons.schedule_rounded)),
                            size: 11,
                            color: isRepaid
                                ? const Color(0xFF1EBE5D)
                                : debt.urgencyColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isRepaid ? 'Settled' : debt.urgencyLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isRepaid
                                  ? const Color(0xFF1EBE5D)
                                  : debt.urgencyColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Status Badge (Due Today, Overdue, Due in X days, Paid on time)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 11, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Settlements & Repayment Breakdown ──
                if (debt.hasPartialSettlements) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.borderOf(context).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Repayment Progress',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                            Text(
                              '${(debt.progressPercent * 100).toInt()}% • Paid ${_formatAmount(debt.totalPaid)} of ${_formatAmount(debt.originalAmount)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isLend ? AppColors.income : AppColors.expense,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: debt.progressPercent,
                            backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.4),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isLend ? AppColors.income : AppColors.expense,
                            ),
                            minHeight: 5,
                          ),
                        ),
                        if (debt.settlements.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...debt.settlements.take(3).map((s) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 13,
                                      color: isLend
                                          ? AppColors.income
                                          : AppColors.expense,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      DateFormat('dd MMM').format(s.date),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimaryOf(context),
                                      ),
                                    ),
                                    if (s.note != null && s.note!.trim().isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          '(${s.note!.trim()})',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textLightOf(context),
                                            fontStyle: FontStyle.italic,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ] else
                                      const Spacer(),
                                    Text(
                                      '+${_formatAmount(s.amount)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isLend
                                            ? AppColors.income
                                            : AppColors.expense,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          if (debt.settlements.length > 3)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+ ${debt.settlements.length - 3} more settlement(s)...',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textLightOf(context),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ] else if (isRepaid) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: (debt.isRepaidOnTime
                              ? AppColors.income
                              : const Color(0xFFFF9800))
                          .withValues(alpha: isDark ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (debt.isRepaidOnTime
                                ? AppColors.income
                                : const Color(0xFFFF9800))
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          debt.isRepaidOnTime
                              ? Icons.verified_rounded
                              : (debt.isRepaidLate
                                  ? Icons.alarm_on_rounded
                                  : Icons.check_circle_rounded),
                          size: 14,
                          color: debt.isRepaidOnTime
                              ? AppColors.income
                              : const Color(0xFFFF9800),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            debt.repaidDate != null
                                ? (debt.isRepaidOnTime
                                    ? 'Paid full ${_formatAmount(debt.originalAmount)} on time (${DateFormat('dd MMM yyyy').format(debt.repaidDate!)})'
                                    : 'Paid full ${_formatAmount(debt.originalAmount)} late by ${debt.daysLateRepaid}d (${DateFormat('dd MMM yyyy').format(debt.repaidDate!)})')
                                : 'Paid in full (${_formatAmount(debt.originalAmount)})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: debt.isRepaidOnTime
                                  ? AppColors.income
                                  : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: AppColors.borderOf(context).withValues(alpha: 0.4),
                ),
                const SizedBox(height: 10),

                // Bottom Action Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.event_outlined,
                          size: 14,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Repay: ${DateFormat('dd MMM yyyy').format(debt.dueDate)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),

                    Row(
                      children: [
                        // Remind Button (Only for Lent and Pending)
                        if (isLend && !isRepaid) ...[
                          _buildActionChip(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Remind',
                            color: const Color(0xFF1EBE5D),
                            bgColor: const Color(0xFF25D366).withValues(alpha: 0.12),
                            borderColor: const Color(0xFF25D366).withValues(alpha: 0.3),
                            onTap: () => _sendReminder(debt),
                          ),
                          const SizedBox(width: 8),
                        ],

                        // Settle button — opens partial settle sheet for pending, reopen for settled
                        if (!isRepaid)
                          _buildActionChip(
                            icon: Icons.payments_outlined,
                            label: isLend ? 'Settle' : 'Repay',
                            color: AppColors.primary,
                            bgColor: AppColors.primary.withValues(alpha: 0.12),
                            borderColor: AppColors.primary.withValues(alpha: 0.3),
                            onTap: () => _showPartialSettleSheet(context, debt),
                          )
                        else
                          _buildActionChip(
                            icon: Icons.undo_rounded,
                            label: 'Reopen',
                            color: AppColors.textSecondaryOf(context),
                            bgColor: AppColors.surfaceOf(context),
                            borderColor: AppColors.borderOf(context),
                            onTap: () => _toggleSettled(debt),
                          ),
                      ],
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
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── EMPTY STATE ───
  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.handshake_outlined,
              size: 48,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No matching records'
                : 'No borrow or lend records yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different name or clear the search'
                : 'Lend money to friends or track what you owe.\nAutomatic expense & income tracking built-in!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => openAddSheet(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add First Record'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── SEND REMINDER SHARE ACTION ───
  Future<void> _sendReminder(DebtModel debt) async {
    HapticFeedback.lightImpact();
    final formattedAmount = _formatAmount(debt.amount);
    final formattedDate = DateFormat('dd MMM yyyy').format(debt.date);
    final formattedDueDate = DateFormat('dd MMM yyyy').format(debt.dueDate);

    final message = '''
Hi ${debt.personName},

Hope you are doing well! Just a friendly reminder regarding the $formattedAmount borrowed on $formattedDate.
As discussed, the expected repayment date was $formattedDueDate.

Please let me know once convenient to transfer. Thank you!''';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Friendly Repayment Reminder ($formattedAmount)',
        ),
      );
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Failed to open share: $e');
      }
    }
  }

  // ─── PARTIAL SETTLE BOTTOM SHEET ───
  Future<void> _showPartialSettleSheet(
    BuildContext context,
    DebtModel debt,
  ) async {
    HapticFeedback.mediumImpact();
    final isLend = debt.isLend;
    final totalAmount = debt.amount;
    final amountCtrl = TextEditingController(
      text: totalAmount.toStringAsFixed(0),
    );
    final noteCtrl = TextEditingController();
    double settledAmount = totalAmount;
    bool recordTxn = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            final accentColor = isLend ? AppColors.income : AppColors.expense;
            final isFullSettle = (settledAmount - totalAmount).abs() < 0.01;
            final remaining = (totalAmount - settledAmount).clamp(0.0, totalAmount);

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardOf(context),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderOf(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.payments_rounded,
                            color: accentColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLend
                                    ? 'Settle Lent Amount'
                                    : 'Record Repayment',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                              Text(
                                '${debt.personName} • Remaining: ${_formatAmount(totalAmount)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(
                            Icons.close_rounded,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Amount input
                    Text(
                      isLend
                          ? 'How much did they pay back?'
                          : 'How much are you repaying?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            '₹',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              decoration: InputDecoration(
                                hintText: '0',
                                hintStyle: TextStyle(
                                  color: AppColors.textLightOf(context),
                                  fontSize: 24,
                                ),
                                border: InputBorder.none,
                              ),
                              onChanged: (v) {
                                final parsed = double.tryParse(v.trim()) ?? 0;
                                setSheet(() {
                                  settledAmount =
                                      parsed.clamp(0.0, totalAmount);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Quick amount shortcuts
                    Row(
                      children: [
                        _quickAmountChip(
                          '25%',
                          (totalAmount * 0.25).roundToDouble(),
                          accentColor,
                          amountCtrl,
                          setSheet,
                          (v) => settledAmount = v,
                        ),
                        const SizedBox(width: 8),
                        _quickAmountChip(
                          '50%',
                          (totalAmount * 0.50).roundToDouble(),
                          accentColor,
                          amountCtrl,
                          setSheet,
                          (v) => settledAmount = v,
                        ),
                        const SizedBox(width: 8),
                        _quickAmountChip(
                          '75%',
                          (totalAmount * 0.75).roundToDouble(),
                          accentColor,
                          amountCtrl,
                          setSheet,
                          (v) => settledAmount = v,
                        ),
                        const SizedBox(width: 8),
                        _quickAmountChip(
                          'Full',
                          totalAmount,
                          accentColor,
                          amountCtrl,
                          setSheet,
                          (v) => settledAmount = v,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Settlement Note Input
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      child: TextField(
                        controller: noteCtrl,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimaryOf(context),
                        ),
                        decoration: InputDecoration(
                          icon: Icon(
                            Icons.edit_note_rounded,
                            size: 18,
                            color: AppColors.textLightOf(context),
                          ),
                          hintText: 'Note (optional, e.g. GPay, Cash, Part 1)',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: AppColors.textLightOf(context),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Summary info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _summaryCell(
                              context,
                              'Settling',
                              _formatAmount(settledAmount.clamp(0.0, totalAmount)),
                              accentColor,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: AppColors.borderOf(context),
                          ),
                          Expanded(
                            child: _summaryCell(
                              context,
                              isFullSettle
                                  ? '✅ Fully Settled'
                                  : 'Remaining',
                              isFullSettle
                                  ? 'Done!'
                                  : _formatAmount(remaining),
                              isFullSettle
                                  ? AppColors.income
                                  : AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Record transaction toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: CheckboxListTile(
                        value: recordTxn,
                        onChanged: (val) =>
                            setSheet(() => recordTxn = val ?? true),
                        activeColor: AppColors.primary,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          isLend
                              ? 'Record as Income in your tracker'
                              : 'Record as Expense in your tracker',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Confirm button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: settledAmount <= 0
                            ? null
                            : () async {
                                final noteText = noteCtrl.text.trim();
                                Navigator.pop(ctx);
                                await _debtService.partialSettle(
                                  debt: debt,
                                  settledAmount: settledAmount.clamp(
                                    0.0,
                                    totalAmount,
                                  ),
                                  recordTransaction: recordTxn,
                                  note: noteText.isNotEmpty ? noteText : null,
                                );
                                final isFully = (settledAmount - totalAmount).abs() < 0.01;
                                if (mounted) {
                                  AppSnackbar.showSuccess(
                                    this.context,
                                    isFully
                                        ? 'Fully settled!'
                                        : 'Partial payment of ${_formatAmount(settledAmount)} recorded.',
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.borderOf(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          isFullSettle
                              ? (isLend ? 'Confirm Full Settlement' : 'Confirm Full Repayment')
                              : (isLend
                                  ? 'Record Partial Settlement'
                                  : 'Record Partial Repayment'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _quickAmountChip(
    String label,
    double amount,
    Color accentColor,
    TextEditingController ctrl,
    StateSetter setSheet,
    void Function(double) onSet,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          final display = amount == amount.truncate()
              ? amount.toInt().toString()
              : amount.toStringAsFixed(2);
          ctrl.text = display;
          setSheet(() => onSet(amount));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCell(
    BuildContext context,
    String label,
    String value,
    Color valueColor,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ─── SETTLE / REOPEN DEBT (Full toggle used for "Reopen") ───
  Future<void> _toggleSettled(DebtModel debt) async {
    HapticFeedback.mediumImpact();
    // Only handles reopening a settled debt
    await _debtService.markAsRepaid(debt: debt, isRepaid: false);
    if (mounted) {
      AppSnackbar.showInfo(context, 'Record reopened as pending');
    }
  }

  // ─── DEBT DETAIL MODAL ───
  void _showDebtDetailModal(BuildContext context, DebtModel debt) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Debt Record Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        color: AppColors.textSecondaryOf(context),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openAddEditSheet(context, existingDebt: debt);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 20, color: AppColors.error),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDelete(context, debt);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailRow(
                context,
                'Person',
                debt.personName,
                Icons.person_outline,
              ),
              _buildDetailRow(
                context,
                'Type',
                debt.isLend ? 'Lent (You gave money)' : 'Borrowed (You took money)',
                debt.isLend ? Icons.arrow_outward_rounded : Icons.arrow_downward_rounded,
                valueColor: debt.isLend ? AppColors.income : AppColors.expense,
              ),
              _buildDetailRow(
                context,
                'Initial Amount',
                '${debt.isLend ? '+' : '-'}${_formatAmount(debt.originalAmount)}',
                Icons.currency_rupee_rounded,
                valueColor: debt.isLend ? AppColors.income : AppColors.expense,
              ),
              if (debt.hasPartialSettlements || debt.isRepaid) ...[
                _buildDetailRow(
                  context,
                  'Total Paid',
                  '${_formatAmount(debt.totalPaid)} (${(debt.progressPercent * 100).toInt()}%)',
                  Icons.task_alt_rounded,
                  valueColor: AppColors.income,
                ),
                _buildDetailRow(
                  context,
                  'Remaining Balance',
                  debt.isRepaid
                      ? '₹0 (Fully Settled)'
                      : '${debt.isLend ? '+' : '-'}${_formatAmount(debt.amount)}',
                  Icons.account_balance_wallet_outlined,
                  valueColor: debt.isRepaid
                      ? AppColors.income
                      : (debt.isLend ? AppColors.income : AppColors.expense),
                ),
              ],
              _buildDetailRow(
                context,
                'Date Initiated',
                DateFormat('EEEE, dd MMMM yyyy').format(debt.date),
                Icons.calendar_today_outlined,
              ),
              _buildDetailRow(
                context,
                'Repayment Expected',
                DateFormat('EEEE, dd MMMM yyyy').format(debt.dueDate),
                Icons.event_outlined,
              ),
              _buildDetailRow(
                context,
                'Repayment Urgency',
                debt.isUrgent
                    ? '🔴 Strict (Urgent / Expected on date)'
                    : (debt.isLenient
                        ? '🟢 Lenient (Flexible / No rush)'
                        : '🟡 Normal (Standard due date)'),
                Icons.bolt_rounded,
                valueColor: debt.urgencyColor,
              ),
              _buildDetailRow(
                context,
                'Status',
                debt.isRepaid
                    ? (debt.isRepaidOnTime
                        ? '✅ Paid on time (${debt.repaidDate != null ? DateFormat('dd MMM yyyy').format(debt.repaidDate!) : "Settled"})'
                        : (debt.isRepaidLate
                            ? '⚠️ Paid ${debt.daysLateRepaid}d late (${debt.repaidDate != null ? DateFormat('dd MMM yyyy').format(debt.repaidDate!) : "Settled"})'
                            : '✅ Settled'))
                    : (debt.isDueToday
                        ? '⏰ Due Today!'
                        : (debt.isOverdue
                            ? '⚠️ Overdue by ${debt.daysDifference.abs()} days'
                            : 'Pending (Due in ${debt.daysDifference} days)')),
                Icons.info_outline,
                valueColor: debt.isRepaid
                    ? (debt.isRepaidOnTime ? AppColors.income : const Color(0xFFFF9800))
                    : (debt.isOverdue
                        ? AppColors.expense
                        : (debt.isDueToday ? const Color(0xFFFF9800) : const Color(0xFF00897B))),
              ),
              if (debt.note != null && debt.note!.isNotEmpty)
                _buildDetailRow(
                  context,
                  'Note',
                  debt.note!,
                  Icons.notes_rounded,
                ),

              // Settlement History Timeline
              if (debt.settlements.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceOf(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.borderOf(context).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 16,
                                color: AppColors.textSecondaryOf(context),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Settlement History (${debt.settlements.length})',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Paid: ${_formatAmount(debt.totalSettled)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: debt.isLend ? AppColors.income : AppColors.expense,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...debt.settlements.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final s = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.cardOf(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.borderOf(context).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: (debt.isLend
                                            ? AppColors.income
                                            : AppColors.expense)
                                        .withValues(alpha: 0.15),
                                    child: Text(
                                      '$idx',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: debt.isLend
                                            ? AppColors.income
                                            : AppColors.expense,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('dd MMMM yyyy').format(s.date),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimaryOf(context),
                                        ),
                                      ),
                                      if (s.note != null && s.note!.trim().isNotEmpty)
                                        Text(
                                          s.note!.trim(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textLightOf(context),
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                '+${_formatAmount(s.amount)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: debt.isLend
                                      ? AppColors.income
                                      : AppColors.expense,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Action buttons in detail modal
              if (!debt.isRepaid) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showPartialSettleSheet(context, debt);
                    },
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: Text(
                      debt.isLend ? 'Settle / Partial Repayment' : 'Record Repayment',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          debt.isLend ? AppColors.income : AppColors.expense,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              if (debt.isLend && !debt.isRepaid)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _sendReminder(debt);
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: const Text('Send Reminder Message'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textLightOf(context)),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CONFIRM DELETE ───
  Future<void> _confirmDelete(BuildContext context, DebtModel debt) async {
    bool deleteLinked = true;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardOf(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                'Delete Record?',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete this debt record for ${debt.personName} (${_formatAmount(debt.amount)})?',
                    style: TextStyle(color: AppColors.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: 12),
                  if (debt.transactionId != null)
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: CheckboxListTile(
                        value: deleteLinked,
                        onChanged: (val) =>
                            setDialogState(() => deleteLinked = val ?? true),
                        activeColor: AppColors.error,
                        dense: true,
                        title: const Text(
                          'Also delete associated Expense/Income transaction',
                          style: TextStyle(fontSize: 11),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondaryOf(context)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _debtService.deleteDebt(
                      debt,
                      deleteLinkedTransactions: deleteLinked,
                    );
                    if (mounted) {
                      AppSnackbar.showSuccess(this.context, 'Record deleted');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── ADD / EDIT BOTTOM SHEET ───
  void _openAddEditSheet(
    BuildContext context, {
    DebtModel? existingDebt,
    int initialType = 0, // 0=Lend, 1=Borrow
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: _AddEditDebtSheet(
            existingDebt: existingDebt,
            initialType: initialType,
            recentContacts: _recentContacts,
            onSaved: () {},
          ),
        );
      },
    );
  }
}

// ─── ADD / EDIT SHEET WIDGET ───
class _AddEditDebtSheet extends StatefulWidget {
  final DebtModel? existingDebt;
  final int initialType; // 0=Lend, 1=Borrow
  final List<String> recentContacts;
  final VoidCallback onSaved;

  const _AddEditDebtSheet({
    this.existingDebt,
    this.initialType = 0,
    required this.recentContacts,
    required this.onSaved,
  });

  @override
  State<_AddEditDebtSheet> createState() => _AddEditDebtSheetState();
}

class _AddEditDebtSheetState extends State<_AddEditDebtSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _personController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  late int _typeIndex; // 0 = Lent (I gave), 1 = Borrowed (I took)
  String _urgency = 'medium'; // 'low', 'medium', 'high'
  DateTime _loanDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  bool _remindOnDueDate = true;
  bool _isSaving = false;

  bool get isEditing => widget.existingDebt != null;

  @override
  void initState() {
    super.initState();
    _typeIndex = widget.initialType;
    if (isEditing) {
      final d = widget.existingDebt!;
      _typeIndex = d.isLend ? 0 : 1;
      _urgency = d.urgency;
      _amountController.text =
          d.amount.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');
      _personController.text = d.personName;
      _noteController.text = d.note ?? '';
      _loanDate = d.date;
      _dueDate = d.dueDate;
      _remindOnDueDate = d.remindOnDueDate;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _personController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isDueDate) async {
    final initial = isDueDate ? _dueDate : _loanDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Theme.of(context).brightness,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isDueDate) {
          _dueDate = picked;
        } else {
          _loanDate = picked;
        }
      });
    }
  }

  void _setQuickDueDate(int days) {
    HapticFeedback.selectionClick();
    setState(() {
      _dueDate = DateTime.now().add(Duration(days: days));
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'Please enter a valid amount');
      return;
    }

    final personName = _personController.text.trim();
    if (personName.isEmpty) {
      AppSnackbar.showError(context, 'Please enter friend or lender name');
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final type = _typeIndex == 0 ? 'lend' : 'borrow';
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      if (isEditing) {
        final updated = widget.existingDebt!.copyWith(
          type: type,
          personName: personName,
          amount: amount,
          date: _loanDate,
          dueDate: _dueDate,
          note: note,
          remindOnDueDate: _remindOnDueDate,
          urgency: _urgency,
        );
        await DebtService.instance.updateDebt(updated);
      } else {
        final newDebt = DebtModel(
          type: type,
          personName: personName,
          amount: amount,
          date: _loanDate,
          dueDate: _dueDate,
          note: note,
          remindOnDueDate: _remindOnDueDate,
          urgency: _urgency,
        );
        await DebtService.instance.addDebt(newDebt);
      }

      widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context);

      final isOnline = NetworkHelper.isOnline.value;
      AppSnackbar.showSuccess(
        context,
        !isOnline
            ? (isEditing
                ? 'Record updated locally! (Will sync when online)'
                : 'Record saved locally! (Will sync when online)')
            : (isEditing
                ? 'Record updated!'
                : (_typeIndex == 0
                    ? 'Lent record saved! (Added to Expenses)'
                    : 'Borrow record saved! (Added to Income)')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppSnackbar.showError(context, 'Error saving: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLend = _typeIndex == 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderOf(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEditing ? 'Edit Record' : 'Record Loan or Debt',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type selector
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _typeIndex = 0);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: isLend
                                      ? AppColors.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.arrow_upward_rounded,
                                        size: 16,
                                        color: isLend
                                            ? Colors.white
                                            : AppColors.textSecondaryOf(context),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'I Lent (Gave)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: isLend
                                              ? Colors.white
                                              : AppColors.textSecondaryOf(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _typeIndex = 1);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: !isLend
                                      ? const Color(0xFFE65100)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.arrow_downward_rounded,
                                        size: 16,
                                        color: !isLend
                                            ? Colors.white
                                            : AppColors.textSecondaryOf(context),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'I Borrowed (Took)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: !isLend
                                              ? Colors.white
                                              : AppColors.textSecondaryOf(context),
                                        ),
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
                    const SizedBox(height: 18),

                    // Amount Field
                    Text(
                      'Amount',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            '₹',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isLend
                                  ? AppColors.primary
                                  : const Color(0xFFE65100),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  color: AppColors.textLightOf(context),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                                border: InputBorder.none,
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter amount';
                                }
                                if (double.tryParse(val.trim()) == null) {
                                  return 'Enter valid number';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Person Name Field
                    Text(
                      isLend ? 'Who did you lend to?' : 'Who did you borrow from?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 20,
                            color: AppColors.textSecondaryOf(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _personController,
                              textCapitalization: TextCapitalization.words,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Friend or Contact Name',
                                hintStyle: TextStyle(
                                  color: AppColors.textLightOf(context),
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Name is required';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Recent contacts chips
                    if (widget.recentContacts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 32,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.recentContacts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 6),
                          itemBuilder: (context, idx) {
                            final name = widget.recentContacts[idx];
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _personController.text = name;
                                });
                              },
                              child: Chip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                backgroundColor:
                                    AppColors.surfaceOf(context),
                                label: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Expected Repayment Date
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Expected Repayment Date',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _pickDate(true),
                          child: Text(
                            'Pick Date',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _pickDate(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.event_available_rounded,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  DateFormat('EEEE, dd MMMM yyyy')
                                      .format(_dueDate),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Due Date Shortcuts
                    Row(
                      children: [
                        _buildQuickDateChip('+3 Days', 3),
                        const SizedBox(width: 6),
                        _buildQuickDateChip('+1 Week', 7),
                        const SizedBox(width: 6),
                        _buildQuickDateChip('+2 Weeks', 14),
                        const SizedBox(width: 6),
                        _buildQuickDateChip('+1 Month', 30),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Urgency Selector
                    Text(
                      'Repayment Urgency',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Set expectations for repayment timeline & reminder priority',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textLightOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildUrgencyOption(
                          value: 'low',
                          label: 'Lenient',
                          subtitle: 'No rush / flexible',
                          color: const Color(0xFF2E7D32),
                          icon: Icons.spa_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildUrgencyOption(
                          value: 'medium',
                          label: 'Normal',
                          subtitle: 'Due on date',
                          color: const Color(0xFFF57C00),
                          icon: Icons.schedule_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildUrgencyOption(
                          value: 'high',
                          label: 'Strict',
                          subtitle: 'Urgent priority',
                          color: const Color(0xFFE53935),
                          icon: Icons.priority_high_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Date Lent / Borrowed
                    Text(
                      isLend ? 'Date Lent' : 'Date Borrowed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _pickDate(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 18,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  DateFormat('dd MMMM yyyy').format(_loanDate),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Note Field
                    Text(
                      'Note / Reason (optional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      child: TextFormField(
                        controller: _noteController,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimaryOf(context),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Dinner bill, Emergency cash',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: AppColors.textLightOf(context),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Remind on due date toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      child: SwitchListTile(
                        value: _remindOnDueDate,
                        onChanged: (val) =>
                            setState(() => _remindOnDueDate = val),
                        activeTrackColor: AppColors.primary,
                        title: Text(
                          'Remind me on repayment day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        subtitle: Text(
                          'Receive a notification reminder on ${DateFormat('dd MMM').format(_dueDate)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Auto-transaction info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLend
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : const Color(0xFFE65100).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isLend
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : const Color(0xFFE65100).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.sync_rounded,
                            size: 18,
                            color: isLend
                                ? AppColors.primary
                                : const Color(0xFFE65100),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isLend
                                  ? '✨ Lending automatically logs an Expense of ₹${_amountController.text.trim().isEmpty ? "0" : _amountController.text.trim()} under "Lending".'
                                  : '✨ Borrowing automatically logs an Income of ₹${_amountController.text.trim().isEmpty ? "0" : _amountController.text.trim()} under "Borrowing".',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isLend
                                    ? AppColors.primary
                                    : const Color(0xFFE65100),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLend
                              ? AppColors.primary
                              : const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                isEditing ? 'Update Record' : 'Save Record',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickDateChip(String label, int days) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _setQuickDueDate(days),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderOf(context),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUrgencyOption({
    required String value,
    required String label,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = _urgency == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _urgency = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.12)
                : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.borderOf(context),
              width: isSelected ? 1.8 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected
                        ? color
                        : AppColors.textSecondaryOf(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? color
                          : AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? color : AppColors.textLightOf(context),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
