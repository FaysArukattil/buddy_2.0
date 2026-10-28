import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/models/category.dart' as cat;
import 'package:buddy/utils/icon_helper.dart';
import 'package:buddy/services/Network_services.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class AddTransactionScreen extends StatefulWidget {
  final Map<String, dynamic>? existingTransaction;

  const AddTransactionScreen({super.key, this.existingTransaction});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen>
    with TickerProviderStateMixin {
  int _typeIndex = 0; // 0 = expense, 1 = income
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  String? _selectedCategoryName;
  IconData? _selectedCategoryIcon;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  static List<cat.Category>? _persistedSortedExpense;
  static List<cat.Category>? _persistedSortedIncome;

  List<cat.Category> _expenseCategories = [];
  List<cat.Category> _incomeCategories = [];
  bool _loadingCategories = true;

  late final AnimationController _saveAnimController;
  late final AnimationController _sliderAnimController;
  final ScrollController _scrollController = ScrollController();

  List<cat.Category> get _currentCategories =>
      _typeIndex == 0 ? _expenseCategories : _incomeCategories;

  bool get _isEditing => widget.existingTransaction != null;

  @override
  void initState() {
    super.initState();
    _saveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _sliderAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: _typeIndex.toDouble(),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    // Initialize categories instantly with 0ms latency from stable cache or defaults
    if (_persistedSortedExpense != null && _persistedSortedExpense!.isNotEmpty) {
      _expenseCategories = List.from(_persistedSortedExpense!);
    } else {
      _expenseCategories = FirestoreService.getInstantCategories('expense');
    }

    if (_persistedSortedIncome != null && _persistedSortedIncome!.isNotEmpty) {
      _incomeCategories = List.from(_persistedSortedIncome!);
    } else {
      _incomeCategories = FirestoreService.getInstantCategories('income');
    }

    _loadingCategories = _expenseCategories.isEmpty && _incomeCategories.isEmpty;
    _setDefaultCategory();

    // Async background sync with Firestore & usage frequencies
    _loadCategories();

    // Pre-fill if editing
    if (_isEditing) {
      final tx = widget.existingTransaction!;
      _amountController.text =
          (tx['amount'] as double).toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');
      _noteController.text = tx['note'] as String? ?? '';
      _selectedDate = tx['date'] as DateTime;
      final type = (tx['type'] as String).toLowerCase().trim();
      _typeIndex = type == 'income' ? 1 : 0;
      _sliderAnimController.value = _typeIndex.toDouble();
      _selectedCategoryName = tx['category'] as String?;
      final iconCode = tx['icon'] as int?;
      if (iconCode != null) {
        _selectedCategoryIcon = IconHelper.getIcon(iconCode);
      }
    }
  }

  @override
  void dispose() {
    _sliderAnimController.dispose();
    _scrollController.dispose();
    _saveAnimController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  void _setSliderIndex(int index) {
    HapticFeedback.lightImpact();
    if (_typeIndex != index) {
      setState(() {
        _typeIndex = index;
        _setDefaultCategory();
      });
    }
    _sliderAnimController.animateTo(
      index.toDouble(),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (mounted) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _setDefaultCategory() {
    if (_isEditing) return; // Don't override existing transaction values
    
    final cats = _typeIndex == 0 ? _expenseCategories : _incomeCategories;
    if (cats.isEmpty) return;

    // Default to first non-'Other' category, fallback to first category
    final defaultCat = cats.firstWhere(
      (c) => c.name.toLowerCase().trim() != 'other',
      orElse: () => cats.first,
    );

    _selectedCategoryName = defaultCat.name;
    _selectedCategoryIcon = defaultCat.icon;
  }

  Future<void> _loadCategories() async {
    try {
      final firestore = FirestoreService.instance;
      
      // Load categories
      final expenseRaw = await firestore.getCategories('expense');
      final incomeRaw = await firestore.getCategories('income');

      // Filter out Lending and Borrowing so they NEVER appear in normal Add Transaction
      final expense = expenseRaw.where((c) {
        final n = c.name.toLowerCase();
        return n != 'lending' && n != 'borrowing';
      }).toList();
      final income = incomeRaw.where((c) {
        final n = c.name.toLowerCase();
        return n != 'lending' && n != 'borrowing';
      }).toList();

      final finalExpense = expense.isNotEmpty
          ? expense
          : FirestoreService.getDefaultCategories('expense');
      final finalIncome = income.isNotEmpty
          ? income
          : FirestoreService.getDefaultCategories('income');
      
      // Fast query for recent transactions to compute usage frequency without downloading entire history
      final usageCounts = <String, int>{};
      try {
        final recentTxns = await firestore.getRecentTransactions(limit: 60);
        for (final txn in recentTxns) {
          final catName = txn.category;
          usageCounts[catName] = (usageCounts[catName] ?? 0) + 1;
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching recent transactions for sorting categories: $e');
      }

      // Sort categories: highest usage count first, alphabetical fallback.
      // "Other" is always pushed to the bottom so it never monopolizes the top slots.
      void sortCategories(List<cat.Category> categories) {
        categories.sort((a, b) {
          final isOtherA = a.name.toLowerCase().trim() == 'other';
          final isOtherB = b.name.toLowerCase().trim() == 'other';
          if (isOtherA && !isOtherB) return 1;
          if (!isOtherA && isOtherB) return -1;

          final countA = usageCounts[a.name] ?? 0;
          final countB = usageCounts[b.name] ?? 0;
          if (countA != countB) {
            return countB.compareTo(countA); // Descending order of usage
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase()); // Alphabetical fallback
        });
      }

      sortCategories(finalExpense);
      sortCategories(finalIncome);

      // Persist sorted order for instant, stable future opens
      _persistedSortedExpense = List.from(finalExpense);
      _persistedSortedIncome = List.from(finalIncome);

      if (mounted) {
        final expenseCountChanged = _expenseCategories.length != finalExpense.length;
        final incomeCountChanged = _incomeCategories.length != finalIncome.length;

        // ONLY setState if categories were previously empty or count changed (e.g. custom category added/deleted).
        // This guarantees categories NEVER jump or shuffle on-screen while the user is looking at them!
        if (_expenseCategories.isEmpty || expenseCountChanged || incomeCountChanged) {
          setState(() {
            _expenseCategories = finalExpense;
            _incomeCategories = finalIncome;
            _loadingCategories = false;

            // If editing, match category by name
            if (_isEditing && _selectedCategoryName != null) {
              final cats = _typeIndex == 0 ? finalExpense : finalIncome;
              for (final c in cats) {
                if (c.name == _selectedCategoryName) {
                  _selectedCategoryIcon = c.icon;
                  break;
                }
              }
            } else if (_selectedCategoryName == null) {
              _setDefaultCategory();
            }
          });
        } else {
          if (_loadingCategories) {
            setState(() => _loadingCategories = false);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading categories: $e');
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _pickDate() async {
    DateTime temp = _selectedDate;
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) {
        final isDark = AppColors.isDark(context);
        return Material(
          type: MaterialType.transparency,
          child: Container(
            height: 320,
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppColors.textSecondaryOf(context),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          setState(() => _selectedDate = temp);
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            decoration: TextDecoration.none,
                          ),
                        ),
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
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      use24hFormat: false,
                      initialDateTime: _selectedDate,
                      maximumDate: DateTime.now().add(const Duration(days: 1)),
                      onDateTimeChanged: (d) {
                        temp = d;
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final double t = _sliderAnimController.value.clamp(0.0, 1.0);
    final themeAccent = t < 0.5 ? AppColors.expense : AppColors.income;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        top: true,
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            HapticFeedback.lightImpact();
          },
          onHorizontalDragUpdate: (details) {
            final screenWidth = MediaQuery.sizeOf(context).width;
            final delta = details.delta.dx / (screenWidth / 2);
            _sliderAnimController.value =
                (_sliderAnimController.value + delta).clamp(0.0, 1.0);
            final int nearest = _sliderAnimController.value.round();
            if (nearest != _typeIndex) {
              setState(() {
                _typeIndex = nearest;
                _setDefaultCategory();
              });
              HapticFeedback.lightImpact();
            }
          },
          onHorizontalDragEnd: (details) {
            final double v = details.primaryVelocity ?? 0;
            int target = _sliderAnimController.value.round();
            if (v > 200) target = 1;
            if (v < -200) target = 0;
            _setSliderIndex(target);
          },
          child: Column(
            children: [
              // ── Hero Header in Signature Emerald/Teal Theme ──
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [
                            Color(0xFF0F2624),
                            Color(0xFF163E3B),
                            Color(0xFF1E5D57),
                          ]
                        : const [
                            Color(0xFF0F3632),
                            Color(0xFF1E5D57),
                            Color(0xFF2C7A72),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                    bottom: Radius.circular(22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Frosted Drag Handle
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Title & Close Button Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isEditing ? 'Edit Transaction' : 'New Transaction',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _typeIndex == 0
                                    ? 'Record an expense you made'
                                    : 'Record income you received',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Slidable Segmented Bar (Expense | Income) in Hero Header
                    _buildSlidableTypeBar(),
                  ],
                ),
              ),

              // ── Scrollable Body ──
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Amount Card with Quick Chips
                      _buildAmountCard(themeAccent),
                      const SizedBox(height: 14),

                      // Category Section
                      _buildCategorySection(),
                      const SizedBox(height: 14),

                      // Note (optional)
                      _buildSectionLabel('Note (optional)'),
                      const SizedBox(height: 8),
                      _buildNoteField(themeAccent),
                      const SizedBox(height: 14),

                      // Date
                      _buildDateSelector(themeAccent),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // ── Pinned Bottom Bar with Save Button (Always Visible & Above Traditional Navbar) ──
              _buildBottomSaveBar(themeAccent, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSaveBar(Color themeAccent, bool isDark) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final systemBottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    // On traditional Android 3-button navbar, systemBottomPadding is ~48dp.
    // On swipe gestures, systemBottomPadding is ~16-20dp.
    // When keyboard is open, bottomInset > 0.
    final double bottomMargin = bottomInset > 0
        ? bottomInset + 8.0
        : math.max(systemBottomPadding, 14.0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        border: Border(
          top: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: isDark ? 0.6 : 0.8),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomMargin),
      child: _buildSaveButton(themeAccent),
    );
  }

  Widget _buildSlidableTypeBar() {
    final isDark = AppColors.isDark(context);
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(3.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final pillWidth = (totalWidth - 2) / 2;

          return AnimatedBuilder(
            animation: _sliderAnimController,
            builder: (context, _) {
              final double t = _sliderAnimController.value.clamp(0.0, 1.0);
              final double leftOffset = t * pillWidth;

              final Color c1 = Color.lerp(
                const Color(0xFFEF4444),
                const Color(0xFF10B981),
                t,
              )!;
              final Color c2 = Color.lerp(
                const Color(0xFFDC2626),
                const Color(0xFF059669),
                t,
              )!;
              final Color borderC = Color.lerp(
                const Color(0xFFEF4444).withValues(alpha: 0.70),
                const Color(0xFF10B981).withValues(alpha: 0.70),
                t,
              )!;
              final Color glowC = Color.lerp(
                const Color(0xFFEF4444).withValues(alpha: 0.35),
                const Color(0xFF10B981).withValues(alpha: 0.35),
                t,
              )!;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {
                  HapticFeedback.lightImpact();
                },
                onHorizontalDragUpdate: (details) {
                  final double delta = details.delta.dx / pillWidth;
                  _sliderAnimController.value =
                      (_sliderAnimController.value + delta).clamp(0.0, 1.0);
                  final int nearest = _sliderAnimController.value.round();
                  if (nearest != _typeIndex) {
                    setState(() {
                      _typeIndex = nearest;
                      _setDefaultCategory();
                    });
                    HapticFeedback.lightImpact();
                  }
                },
                onHorizontalDragEnd: (details) {
                  final double v = details.primaryVelocity ?? 0;
                  int target = _sliderAnimController.value.round();
                  if (v > 200) target = 1;
                  if (v < -200) target = 0;
                  _setSliderIndex(target);
                },
                child: SizedBox(
                  height: 42,
                  child: Stack(
                    children: [
                      Positioned(
                        left: leftOffset,
                        width: pillWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [c1, c2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: borderC, width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: glowC,
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
                              onTap: () => _setSliderIndex(0),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.south_west_rounded,
                                      size: 14,
                                      color: Color.lerp(
                                        Colors.white,
                                        Colors.white.withValues(alpha: 0.65),
                                        t,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Expense',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: t < 0.5
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: Color.lerp(
                                          Colors.white,
                                          Colors.white.withValues(alpha: 0.65),
                                          t,
                                        ),
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
                              onTap: () => _setSliderIndex(1),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.north_east_rounded,
                                      size: 14,
                                      color: Color.lerp(
                                        Colors.white.withValues(alpha: 0.65),
                                        Colors.white,
                                        t,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Income',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: t >= 0.5
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: Color.lerp(
                                          Colors.white,
                                          Colors.white.withValues(alpha: 0.65),
                                          t,
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
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAmountCard(Color themeAccent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.8),
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '₹',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: themeAccent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _amountController,
              focusNode: _amountFocus,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimaryOf(context),
                letterSpacing: -0.3,
              ),
              cursorColor: themeAccent,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textLightOf(context),
                  letterSpacing: -0.3,
                ),
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_amountController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _amountController.clear());
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context).withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.borderOf(context).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Amount',
                style: TextStyle(
                  color: AppColors.textSecondaryOf(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: AppColors.textSecondaryOf(context),
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }

  Widget _buildCategorySection() {
    if (_loadingCategories) {
      return _buildCategoryShimmer();
    }

    // Exclude "Other" from the visible top-6 grid, keeping it tucked inside More Categories
    final visibleCategories = _currentCategories
        .where((c) => c.name.toLowerCase().trim() != 'other')
        .toList();
    final top6 = visibleCategories.take(6).toList();
    final isSelectedInTop6 = top6.any((c) => c.name == _selectedCategoryName);
    cat.Category? selectedCategory;
    if (!isSelectedInTop6 && _selectedCategoryName != null) {
      selectedCategory = _currentCategories.firstWhere(
        (c) => c.name == _selectedCategoryName,
        orElse: () => cat.Category(
          id: '',
          name: _selectedCategoryName!,
          icon: _selectedCategoryIcon ?? Icons.category_rounded,
          color: AppColors.getCategoryColor(_selectedCategoryName!),
          type: _typeIndex == 0 ? 'expense' : 'income',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel('Category'),
            GestureDetector(
              onTap: () => _showAllCategoriesSheet(context),
              child: Row(
                children: [
                  Text(
                    'View All (${_currentCategories.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final double maxWidth = constraints.maxWidth;
            final int crossAxisCount = maxWidth > 650
                ? 4
                : (maxWidth > 460 ? 3 : 2);
            const double spacing = 10.0;
            final double itemWidth =
                (maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;

            final totalCategories = _currentCategories.length;
            final remainingCount = totalCategories > top6.length
                ? totalCategories - top6.length
                : 0;

            return Column(
              children: [
                // Responsive Grid of Top 6 categories
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: top6
                      .map((c) => SizedBox(
                            width: itemWidth,
                            child: _buildCategoryChip(c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                // If selected category is outside top 6, show it alongside More button, or show full-width More button
                if (selectedCategory != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildCategoryChip(selectedCategory),
                      ),
                      const SizedBox(width: spacing),
                      Expanded(
                        child: _buildAddOrMoreChip(remainingCount),
                      ),
                    ],
                  ),
                ] else ...[
                  _buildMoreCategoriesChip(remainingCount),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Color _getCategoryTextColor({
    required Color catColor,
    required bool isDark,
    required bool isSelected,
  }) {
    if (!isSelected) {
      return AppColors.textPrimaryOf(context);
    }
    if (isDark) {
      // In dark mode, if category color is very dark, brighten it slightly for high readability
      return catColor.computeLuminance() < 0.22
          ? Color.lerp(catColor, Colors.white, 0.40)!
          : catColor;
    } else {
      // In light mode, if category color is very bright, darken it slightly for high contrast against light card
      return catColor.computeLuminance() > 0.42
          ? Color.lerp(catColor, Colors.black, 0.35)!
          : catColor;
    }
  }

  Widget _buildCategoryChip(cat.Category category) {
    final isSelected = _selectedCategoryName == category.name;
    final catColor = AppColors.getCategoryColor(category.name);
    final isDark = AppColors.isDark(context);

    // Selected state uses the category's unique color for clear visual recognition
    final Color backgroundColor = isSelected
        ? catColor.withValues(alpha: isDark ? 0.16 : 0.09)
        : AppColors.cardOf(context);

    final Color borderColor = isSelected
        ? catColor
        : AppColors.borderOf(context).withValues(alpha: isDark ? 0.7 : 0.85);

    final Color textColor = _getCategoryTextColor(
      catColor: catColor,
      isDark: isDark,
      isSelected: isSelected,
    );

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedCategoryName = category.name;
          _selectedCategoryIcon = category.icon;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: catColor.withValues(alpha: isDark ? 0.35 : 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Circular Avatar with Category Color
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: catColor.withValues(
                  alpha: isSelected
                      ? (isDark ? 0.28 : 0.18)
                      : (isDark ? 0.16 : 0.12),
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? catColor.withValues(alpha: 0.65)
                      : catColor.withValues(alpha: 0.28),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Icon(
                category.icon,
                size: 17,
                color: catColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12.5,
                      height: 1.2,
                      color: textColor,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Selected',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: textColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: catColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: catColor.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.check,
                  size: 10,
                  color: catColor.computeLuminance() > 0.55
                      ? Colors.black87
                      : Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMoreCategoriesChip(int remainingCount) {
    return GestureDetector(
      onTap: () => _showAllCategoriesSheet(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'More Categories',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: AppColors.primary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    remainingCount > 0
                        ? '+$remainingCount more options'
                        : 'View all category options',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 10,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOrMoreChip(int remainingCount) {
    return GestureDetector(
      onTap: () => _showAllCategoriesSheet(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'More (${_currentCategories.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAllCategoriesSheet(BuildContext context) async {
    String query = '';
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
            final filtered = _currentCategories.where((c) {
              if (query.isEmpty) return true;
              return c.name.toLowerCase().contains(query.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.85,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.cardOf(sheetContext),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                    blurRadius: 28,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // ── Signature Homescreen-Style Emerald Top Portion ──
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? const [
                                Color(0xFF0F2624),
                                Color(0xFF163E3B),
                                Color(0xFF1E5D57),
                              ]
                            : const [
                                Color(0xFF0F3632),
                                Color(0xFF1E5D57),
                                Color(0xFF2C7A72),
                              ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                        bottom: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag Handle
                        Center(
                          child: Container(
                            width: 38,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Title & Actions Row (Title + Add Button + Close Button)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                              child: const Icon(
                                Icons.category_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_typeIndex == 0 ? 'Expense' : 'Income'} Categories',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    '${filtered.length} categories available',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Add Category Button
                            GestureDetector(
                              onTap: () async {
                                Navigator.pop(sheetContext);
                                await _showCreateCategory(this.context);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 6.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_rounded, color: Colors.white, size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      'Add',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Close Button
                            GestureDetector(
                              onTap: () => Navigator.pop(sheetContext),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 17,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Search Bar Inside Top Portion
                        Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.20),
                            ),
                          ),
                          child: TextField(
                            onChanged: (v) => setSheetState(() => query = v.trim()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                            ),
                            cursorColor: Colors.white,
                            decoration: InputDecoration(
                              hintText: 'Search categories...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.60),
                                fontSize: 13,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Colors.white.withValues(alpha: 0.70),
                                size: 18,
                              ),
                              suffixIcon: query.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () => setSheetState(() => query = ''),
                                      child: Icon(
                                        Icons.close_rounded,
                                        color: Colors.white.withValues(alpha: 0.85),
                                        size: 16,
                                      ),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Rest Below: Categories Grid ──
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 40,
                                  color: AppColors.textLightOf(sheetContext),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No categories found',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondaryOf(sheetContext),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : LayoutBuilder(
                            builder: (sheetCtx, sheetConstraints) {
                              final int crossAxisCount = sheetConstraints.maxWidth > 650
                                  ? 4
                                  : (sheetConstraints.maxWidth > 460 ? 3 : 2);
                              return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                                physics: const BouncingScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: crossAxisCount > 2 ? 2.6 : 2.3,
                                ),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final catItem = filtered[i];
                              final isSelected = _selectedCategoryName == catItem.name;
                              final catColor = AppColors.getCategoryColor(catItem.name);
                              final isCustom = !catItem.isDefault;

                              return _buildSheetCategoryTile(
                                category: catItem,
                                isSelected: isSelected,
                                catColor: catColor,
                                isCustom: isCustom,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _selectedCategoryName = catItem.name;
                                    _selectedCategoryIcon = catItem.icon;
                                  });
                                  Navigator.pop(sheetContext);
                                },
                                onDelete: isCustom
                                    ? () async {
                                        final confirm = await _showDeleteCategoryDialog(catItem);
                                        if (confirm == true) {
                                          await _deleteCategory(catItem);
                                          setSheetState(() {});
                                        }
                                      }
                                    : null,
                              );
                            },
                          );
                        },
                      ),
                  ),
                  const _KeyboardSpacer(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetCategoryTile({
    required cat.Category category,
    required bool isSelected,
    required Color catColor,
    required bool isCustom,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color backgroundColor = isSelected
        ? catColor.withValues(alpha: isDark ? 0.16 : 0.09)
        : AppColors.cardOf(context);

    final Color borderColor = isSelected
        ? catColor
        : AppColors.borderOf(context).withValues(alpha: isDark ? 0.7 : 0.85);

    final Color textColor = _getCategoryTextColor(
      catColor: catColor,
      isDark: isDark,
      isSelected: isSelected,
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: catColor.withValues(alpha: isDark ? 0.35 : 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: catColor.withValues(
                  alpha: isSelected
                      ? (isDark ? 0.28 : 0.18)
                      : (isDark ? 0.16 : 0.12),
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? catColor.withValues(alpha: 0.65)
                      : catColor.withValues(alpha: 0.28),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Icon(
                category.icon,
                size: 16,
                color: catColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                  color: textColor,
                ),
              ),
            ),
            if (isCustom && onDelete != null)
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 14,
                    color: Color(0xFFEF4444),
                  ),
                ),
              )
            else if (isSelected)
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: catColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: catColor.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.check,
                  size: 10,
                  color: catColor.computeLuminance() > 0.55
                      ? Colors.black87
                      : Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showDeleteCategoryDialog(cat.Category category) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.cardOf(context),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Category?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${category.name}"?\n\n'
          'Existing transactions with this category will remain intact, '
          'but this category will be removed from your list.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(cat.Category category) async {
    try {
      if (category.id.isNotEmpty && category.id != category.name) {
        await FirestoreService.instance.deleteCategory(category.id);
      }
      setState(() {
        if (_typeIndex == 0) {
          _expenseCategories.removeWhere((c) => c.name == category.name);
          _persistedSortedExpense = List.from(_expenseCategories);
        } else {
          _incomeCategories.removeWhere((c) => c.name == category.name);
          _persistedSortedIncome = List.from(_incomeCategories);
        }
        if (_selectedCategoryName == category.name) {
          _setDefaultCategory();
        }
      });
      if (mounted) {
        AppSnackbar.showSuccess(context, 'Category "${category.name}" deleted');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Failed to delete category: $e');
      }
    }
  }

  Widget _buildCategoryShimmer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        final int crossAxisCount = maxWidth > 650
            ? 4
            : (maxWidth > 460 ? 3 : 2);
        const double spacing = 10.0;
        final double totalSpacing = spacing * (crossAxisCount - 1);
        final double itemWidth = (maxWidth - totalSpacing) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(
            6,
            (_) => Container(
              width: itemWidth,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoteField(Color themeAccent) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: TextField(
        controller: _noteController,
        textCapitalization: TextCapitalization.sentences,
        maxLines: 2,
        minLines: 1,
        scrollPadding: const EdgeInsets.only(bottom: 40),
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimaryOf(context),
        ),
        cursorColor: themeAccent,
        decoration: InputDecoration(
          hintText: 'e.g., Lunch with friends, Groceries...',
          hintStyle: TextStyle(
            fontSize: 13,
            color: AppColors.textLightOf(context),
          ),
          border: InputBorder.none,
          icon: Icon(
            Icons.edit_note_rounded,
            size: 20,
            color: themeAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector(Color themeAccent) {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = _selectedDate.year == yesterday.year &&
        _selectedDate.month == yesterday.month &&
        _selectedDate.day == yesterday.day;
    final isCustom = !isToday && !isYesterday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Date'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final isTight = constraints.maxWidth < 335;
            if (isTight) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildDateChip('Today', isToday, themeAccent, () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedDate = now);
                  }),
                  _buildDateChip('Yesterday', isYesterday, themeAccent, () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedDate = yesterday);
                  }),
                  _buildCustomDateButton(isCustom, themeAccent),
                ],
              );
            }

            return Row(
              children: [
                _buildDateChip('Today', isToday, themeAccent, () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedDate = now);
                }),
                const SizedBox(width: 8),
                _buildDateChip('Yesterday', isYesterday, themeAccent, () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedDate = yesterday);
                }),
                const Spacer(),
                _buildCustomDateButton(isCustom, themeAccent),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildDateChip(
    String label,
    bool isSelected,
    Color themeAccent,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? themeAccent.withValues(alpha: 0.14)
              : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? themeAccent
                : AppColors.borderOf(context).withValues(alpha: 0.8),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? themeAccent : AppColors.textSecondaryOf(context),
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDateButton(bool isCustom, Color themeAccent) {
    return GestureDetector(
      onTap: _pickDate,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isCustom
              ? themeAccent.withValues(alpha: 0.14)
              : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCustom
                ? themeAccent
                : AppColors.borderOf(context).withValues(alpha: 0.8),
            width: isCustom ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: isCustom ? themeAccent : AppColors.textSecondaryOf(context),
            ),
            const SizedBox(width: 5),
            Text(
              _formatDate(_selectedDate),
              style: TextStyle(
                fontWeight: isCustom ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
                color: isCustom ? themeAccent : AppColors.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton(Color themeAccent) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: themeAccent.withValues(alpha: 0.32),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: themeAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          onPressed: _isSaving ? null : _saveTransaction,
          icon: _isSaving
              ? const SizedBox.shrink()
              : const Icon(Icons.check_circle_rounded, size: 19),
          label: _isSaving
              ? const BuddyLoadingIndicator(size: 22)
              : Text(
                  _isEditing
                      ? 'Update ${_typeIndex == 0 ? 'Expense' : 'Income'}'
                      : 'Save ${_typeIndex == 0 ? 'Expense' : 'Income'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      _showError('Please enter an amount');
      return;
    }
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      _showError('Please enter a valid amount');
      return;
    }
    if (_selectedCategoryName == null) {
      _showError('Please select a category');
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final type = _typeIndex == 0 ? 'expense' : 'income';
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final iconCodePoint = _selectedCategoryIcon?.codePoint ?? Icons.category_rounded.codePoint;

    final now = DateTime.now();
    final dateWithTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      now.hour,
      now.minute,
      now.second,
    );

    final firestore = FirestoreService.instance;

    try {
      if (_isEditing) {
        final id = widget.existingTransaction!['id'] as String;
        await firestore.updateTransaction(id, {
          'amount': amount.abs(),
          'type': type,
          'date': dateWithTime,
          'note': note,
          'category': _selectedCategoryName,
          'icon': iconCodePoint,
        });
        if (!mounted) return;
        final isOnline = NetworkHelper.isOnline.value;
        _showSuccess(isOnline ? 'Transaction updated!' : 'Transaction updated locally! (Will sync when online)');
      } else {
        final txn = TransactionModel(
          amount: amount.abs(),
          type: type,
          date: dateWithTime,
          note: note,
          category: _selectedCategoryName!,
          icon: iconCodePoint,
        );
        await firestore.addTransaction(txn);
        if (!mounted) return;
        final isOnline = NetworkHelper.isOnline.value;
        _showSuccess(isOnline ? 'Transaction saved!' : 'Transaction saved locally! (Will sync when online)');
      }

      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('❌ Error saving transaction: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Failed to save. Please try again.');
    }
  }

  Future<void> _showCreateCategory(BuildContext context) async {
    final nameCtrl = TextEditingController();
    IconData? pickedIcon = Icons.restaurant_rounded;
    Color pickedColor = AppColors.curatedCategoryColors.first;

    final icons = _iconChoices;

    final result = await showModalBottomSheet<cat.Category>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isDark = AppColors.isDark(modalCtx);
            final previewColor = pickedColor;
            final canSave = nameCtrl.text.trim().isNotEmpty && pickedIcon != null;

            return Container(
              decoration: BoxDecoration(
                color: AppColors.cardOf(modalCtx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: AppColors.elevatedShadow,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag Handle
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Header with close
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: previewColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                pickedIcon ?? Icons.category_rounded,
                                color: previewColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Create Category',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimaryOf(modalCtx),
                                    ),
                                  ),
                                  Text(
                                    'Add a custom ${_typeIndex == 0 ? "expense" : "income"} category',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textSecondaryOf(modalCtx),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.of(modalCtx).pop(),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceOf(modalCtx),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: AppColors.textSecondaryOf(modalCtx),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Live Preview Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: previewColor.withValues(alpha: isDark ? 0.16 : 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: previewColor.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: previewColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: previewColor.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  pickedIcon ?? Icons.category_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nameCtrl.text.trim().isEmpty ? 'Category Preview' : nameCtrl.text.trim(),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimaryOf(modalCtx),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_typeIndex == 0 ? "Expense" : "Income"} • Custom Category',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondaryOf(modalCtx),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: previewColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'PREVIEW',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: previewColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Category Name field
                        Text(
                          'Category Name',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(modalCtx),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          style: TextStyle(
                            color: AppColors.textPrimaryOf(modalCtx),
                            fontWeight: FontWeight.w600,
                          ),
                          onChanged: (_) => setModalState(() {}),
                          decoration: InputDecoration(
                            hintText: 'e.g., Starbucks, Books, Gym',
                            hintStyle: TextStyle(
                              color: AppColors.textLightOf(modalCtx),
                              fontWeight: FontWeight.w400,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceOf(modalCtx),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: AppColors.borderOf(modalCtx),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: AppColors.borderOf(modalCtx),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: previewColor,
                                width: 1.8,
                              ),
                            ),
                            suffixIcon: nameCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    color: AppColors.textSecondaryOf(modalCtx),
                                    onPressed: () {
                                      nameCtrl.clear();
                                      setModalState(() {});
                                    },
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Choose Color Section
                        Text(
                          'Category Color',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(modalCtx),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: AppColors.curatedCategoryColors.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, index) {
                              final color = AppColors.curatedCategoryColors[index];
                              final isColorSelected = pickedColor == color;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setModalState(() => pickedColor = color);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isColorSelected ? Colors.white : Colors.transparent,
                                      width: 2.5,
                                    ),
                                    boxShadow: isColorSelected
                                        ? [
                                            BoxShadow(
                                              color: color.withValues(alpha: 0.5),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: isColorSelected
                                      ? const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Pick Icon Section
                        Text(
                          'Choose Icon',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(modalCtx),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: icons.length,
                          itemBuilder: (c, i) {
                            final ic = icons[i];
                            final isSelected = pickedIcon == ic;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setModalState(() => pickedIcon = ic);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? previewColor.withValues(alpha: 0.18)
                                      : AppColors.surfaceOf(modalCtx),
                                  border: Border.all(
                                    color: isSelected ? previewColor : AppColors.borderOf(modalCtx),
                                    width: isSelected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  ic,
                                  color: isSelected ? previewColor : AppColors.textSecondaryOf(modalCtx),
                                  size: 22,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // Create Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: canSave
                                ? () async {
                                    final name = nameCtrl.text.trim();
                                    final newCat = cat.Category(
                                      id: '',
                                      name: name,
                                      icon: pickedIcon!,
                                      color: pickedColor,
                                      type: _typeIndex == 0 ? 'expense' : 'income',
                                      isDefault: false,
                                      order: _currentCategories.length,
                                    );

                                    // Register dynamic color in session
                                    AppColors.registerCategoryColor(name, pickedColor);

                                    try {
                                      final id = await FirestoreService.instance.addCategory(newCat);
                                      if (!modalCtx.mounted) return;
                                      Navigator.of(modalCtx).pop(newCat.copyWith(id: id));
                                    } catch (e) {
                                      debugPrint('❌ Error adding category: $e');
                                    }
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: previewColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.borderOf(modalCtx),
                              disabledForegroundColor: AppColors.textLightOf(modalCtx),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: canSave ? 3 : 0,
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_rounded, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Save Category',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
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
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        if (_typeIndex == 0) {
          _expenseCategories.add(result);
          _persistedSortedExpense = List.from(_expenseCategories);
        } else {
          _incomeCategories.add(result);
          _persistedSortedIncome = List.from(_incomeCategories);
        }
        _selectedCategoryName = result.name;
        _selectedCategoryIcon = result.icon;
      });
      _showSuccess('Category "${result.name}" added');
    }
  }

  List<IconData> get _iconChoices => const [
        Icons.restaurant_rounded,
        Icons.fastfood_rounded,
        Icons.coffee_rounded,
        Icons.delivery_dining_rounded,
        Icons.shopping_cart_rounded,
        Icons.shopping_bag_rounded,
        Icons.local_gas_station_rounded,
        Icons.directions_car_rounded,
        Icons.local_taxi_rounded,
        Icons.two_wheeler_rounded,
        Icons.flight_rounded,
        Icons.movie_rounded,
        Icons.tv_rounded,
        Icons.ondemand_video_rounded,
        Icons.music_note_rounded,
        Icons.live_tv_rounded,
        Icons.fitness_center_rounded,
        Icons.medical_services_rounded,
        Icons.school_rounded,
        Icons.home_rounded,
        Icons.receipt_long_rounded,
        Icons.phone_android_rounded,
        Icons.bolt_rounded,
        Icons.storefront_rounded,
        Icons.inventory_2_rounded,
        Icons.checkroom_rounded,
        Icons.celebration_rounded,
        Icons.volunteer_activism_rounded,
        Icons.payments_rounded,
        Icons.work_outline_rounded,
        Icons.business_center_rounded,
        Icons.trending_up_rounded,
        Icons.savings_rounded,
        Icons.card_giftcard_rounded,
        Icons.currency_exchange_rounded,
        Icons.house_rounded,
        Icons.autorenew_rounded,
        Icons.pets_rounded,
        Icons.sports_esports_rounded,
        Icons.category_rounded,
      ];

  void _showError(String message) {
    AppSnackbar.showError(context, message);
  }

  void _showSuccess(String message) {
    AppSnackbar.showSuccess(
      context,
      message,
      duration: const Duration(milliseconds: 1500),
    );
  }

  String _formatDate(DateTime dt) {
    final months = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ─── KEYBOARD SPACER (Isolates insets listener from main sheet) ───
class _KeyboardSpacer extends StatelessWidget {
  const _KeyboardSpacer();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final systemBottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final targetHeight =
        bottomInset > 0 ? bottomInset : math.max(systemBottomPadding, 12.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: targetHeight,
    );
  }
}

