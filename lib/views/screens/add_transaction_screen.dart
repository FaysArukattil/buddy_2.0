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

  List<cat.Category> _expenseCategories = [];
  List<cat.Category> _incomeCategories = [];
  bool _loadingCategories = true;

  late final AnimationController _saveAnimController;

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

    // Initialize categories instantly with 0ms latency from cache/preset
    final instantExpense = FirestoreService.getInstantCategories('expense');
    final instantIncome = FirestoreService.getInstantCategories('income');
    _expenseCategories = instantExpense;
    _incomeCategories = instantIncome;
    _loadingCategories = instantExpense.isEmpty && instantIncome.isEmpty;
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
      _selectedCategoryName = tx['category'] as String?;
      final iconCode = tx['icon'] as int?;
      if (iconCode != null) {
        _selectedCategoryIcon = IconHelper.getIcon(iconCode);
      }
    }

    // Auto-focus amount field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isEditing) {
        _amountFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _saveAnimController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  void _setDefaultCategory() {
    if (_isEditing) return; // Don't override existing transaction values
    
    final cats = _typeIndex == 0 ? _expenseCategories : _incomeCategories;
    if (cats.isEmpty) return;

    // Default to "Other" if available, otherwise first category in the list
    final otherCat = cats.firstWhere(
      (c) => c.name.toLowerCase() == 'other',
      orElse: () => cats.first,
    );

    _selectedCategoryName = otherCat.name;
    _selectedCategoryIcon = otherCat.icon;
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

      // Sort categories: highest usage count first, alphabetical fallback
      void sortCategories(List<cat.Category> categories) {
        categories.sort((a, b) {
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

      if (mounted) {
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
        return Container(
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
                        style: TextStyle(color: AppColors.textSecondaryOf(context)),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() => _selectedDate = temp);
                      },
                      child: Text(
                        'Done',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  _buildCloseButton(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing ? 'Edit Transaction' : 'New Transaction',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimaryOf(context),
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          _typeIndex == 0
                              ? 'Record an expense you made'
                              : 'Record income you received',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Type Toggle ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTypeToggle(),
            ),
            const SizedBox(height: 14),

            // ── Scrollable Content ──
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Amount Card ──
                    _buildAmountCard(),
                    const SizedBox(height: 18),

                    // ── Category Section ──
                    _buildCategorySection(),
                    const SizedBox(height: 20),

                    // ── Note ──
                    _buildSectionLabel('Note (optional)'),
                    const SizedBox(height: 8),
                    _buildNoteField(),
                    const SizedBox(height: 18),

                    // ── Date ──
                    _buildDateSelector(),
                    const SizedBox(height: 24),

                    // ── Save Button ──
                    _buildSaveButton(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.close_rounded,
          size: 20,
          color: AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          _buildToggleOption('Expense', 0),
          _buildToggleOption('Income', 1),
        ],
      ),
    );
  }

  Widget _buildToggleOption(String label, int index) {
    final isSelected = _typeIndex == index;
    final color = index == 0 ? AppColors.expense : AppColors.income;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_typeIndex != index) {
            HapticFeedback.selectionClick();
            setState(() {
              _typeIndex = index;
              _setDefaultCategory();
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondaryOf(context),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountCard() {
    final typeColor = _typeIndex == 0 ? AppColors.expense : AppColors.income;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      child: Column(
        children: [
          Text(
            _typeIndex == 0 ? 'How much did you spend?' : 'How much did you earn?',
            style: TextStyle(
              color: AppColors.textSecondaryOf(context),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '₹',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: typeColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 60, maxWidth: 260),
                  child: TextField(
                    controller: _amountController,
                    focusNode: _amountFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: typeColor,
                      letterSpacing: -1,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '0',
                      hintStyle: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: typeColor.withValues(alpha: 0.25),
                        letterSpacing: -1,
                      ),
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Quick amount addition chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildQuickAmountChip('+100', 100, typeColor),
              _buildQuickAmountChip('+500', 500, typeColor),
              _buildQuickAmountChip('+1,000', 1000, typeColor),
              _buildQuickAmountChip('+2,000', 2000, typeColor),
              _buildQuickClearChip(typeColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAmountChip(String label, double addVal, Color typeColor) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        final current = double.tryParse(_amountController.text.trim()) ?? 0.0;
        final newVal = (current + addVal);
        final text = newVal == newVal.truncate()
            ? newVal.toInt().toString()
            : newVal.toStringAsFixed(2);
        _amountController.text = text;
        _amountController.selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: typeColor.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: typeColor,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickClearChip(Color typeColor) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _amountController.clear();
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.borderOf(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.backspace_outlined,
              size: 13,
              color: AppColors.textSecondaryOf(context),
            ),
            const SizedBox(width: 4),
            Text(
              'Clear',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
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

    final top4 = _currentCategories.take(4).toList();
    final isSelectedInTop4 = top4.any((c) => c.name == _selectedCategoryName);
    cat.Category? selectedCategory;
    if (!isSelectedInTop4 && _selectedCategoryName != null) {
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
            const double spacing = 10.0;
            final double itemWidth = (constraints.maxWidth - spacing) / 2;

            return Column(
              children: [
                // 2x2 Grid of Top 4 categories
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: top4
                      .map((c) => SizedBox(
                            width: itemWidth,
                            child: _buildCategoryChip(c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                // If selected category is outside top 4, show it alongside More button, or show full-width More button
                if (selectedCategory != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildCategoryChip(selectedCategory),
                      ),
                      const SizedBox(width: spacing),
                      Expanded(
                        child: _buildAddOrMoreChip(
                            _currentCategories.length > 4 ? _currentCategories.length - 4 : 0),
                      ),
                    ],
                  ),
                ] else ...[
                  _buildMoreCategoriesChip(
                      _currentCategories.length > 4 ? _currentCategories.length - 4 : 0),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCategoryChip(cat.Category category) {
    final isSelected = _selectedCategoryName == category.name;
    final catColor = AppColors.getCategoryColor(category.name);

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
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? catColor
              : catColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? catColor : catColor.withValues(alpha: 0.22),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: catColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : catColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                category.icon,
                size: 19,
                color: isSelected ? Colors.white : catColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isSelected
                          ? Colors.white
                          : AppColors.textPrimaryOf(context),
                    ),
                  ),
                  if (isSelected)
                    Text(
                      'Selected',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Colors.white,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreCategoriesChip(int remainingCount) {
    return GestureDetector(
      onTap: () => _showAllCategoriesSheet(context),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1.5,
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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'More Categories',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    remainingCount > 0
                        ? '+$remainingCount more options'
                        : 'View all category options',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 11,
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
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                size: 18,
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
                  fontSize: 12.5,
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
                  // Signature Curved Emerald Header
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
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                size: 20,
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
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  Text(
                                    '${filtered.length} categories available • Tap to select',
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
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Search bar & Add category button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setSheetState(() => query = v.trim()),
                            style: TextStyle(
                              color: AppColors.textPrimaryOf(sheetContext),
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search categories...',
                              hintStyle: TextStyle(
                                color: AppColors.textLightOf(sheetContext),
                                fontSize: 13,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: AppColors.textLightOf(sheetContext),
                                size: 18,
                              ),
                              suffixIcon: query.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () => setSheetState(() => query = ''),
                                      child: Icon(
                                        Icons.close_rounded,
                                        color: AppColors.textSecondaryOf(sheetContext),
                                        size: 16,
                                      ),
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.surfaceOf(sheetContext),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppColors.borderOf(sheetContext),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppColors.borderOf(sheetContext),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _showCreateCategory(this.context);
                          },
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('Add'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Categories grid
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
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            physics: const BouncingScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 2.3,
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
                          ),
                  ),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? catColor
              : catColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? catColor : catColor.withValues(alpha: 0.22),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: catColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : catColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                category.icon,
                size: 17,
                color: isSelected ? Colors.white : catColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: isSelected
                      ? Colors.white
                      : AppColors.textPrimaryOf(context),
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
                    size: 15,
                    color: Color(0xFFEF4444),
                  ),
                ),
              )
            else if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Colors.white,
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
        } else {
          _incomeCategories.removeWhere((c) => c.name == category.name);
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
        const double spacing = 10.0;
        const int crossAxisCount = 2;
        const double totalSpacing = spacing * (crossAxisCount - 1);
        final double itemWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(
            4,
            (_) => Container(
              width: itemWidth,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoteField() {
    return TextField(
      controller: _noteController,
      textCapitalization: TextCapitalization.sentences,
      maxLines: 1,
      style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 15),
      decoration: InputDecoration(
        hintText: 'e.g., Lunch with friends',
        hintStyle: TextStyle(color: AppColors.textLightOf(context), fontSize: 14),
        filled: true,
        fillColor: AppColors.cardOf(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = _selectedDate.year == yesterday.year &&
        _selectedDate.month == yesterday.month &&
        _selectedDate.day == yesterday.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Date'),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildDateChip('Today', isToday, () {
              HapticFeedback.selectionClick();
              setState(() => _selectedDate = now);
            }),
            const SizedBox(width: 8),
            _buildDateChip('Yesterday', isYesterday, () {
              HapticFeedback.selectionClick();
              setState(() => _selectedDate = yesterday);
            }),
            const Spacer(),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (!isToday && !isYesterday)
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.cardOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (!isToday && !isYesterday)
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : AppColors.borderOf(context),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: (!isToday && !isYesterday)
                          ? AppColors.primary
                          : AppColors.textSecondaryOf(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(_selectedDate),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: (!isToday && !isYesterday)
                            ? AppColors.primary
                            : AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderOf(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondaryOf(context),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    final typeColor = _typeIndex == 0 ? AppColors.expense : AppColors.income;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: typeColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: _isSaving ? null : _saveTransaction,
        child: _isSaving
            ? const BuddyLoadingIndicator(size: 24)
            : Text(
                _isEditing
                    ? 'Update ${_typeIndex == 0 ? 'Expense' : 'Income'}'
                    : 'Add ${_typeIndex == 0 ? 'Expense' : 'Income'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
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
        } else {
          _incomeCategories.add(result);
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
