import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/models/category.dart' as cat;

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
  String _categoryQuery = '';

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
        // ignore: non_const_argument_for_const_parameter
        _selectedCategoryIcon = IconData(iconCode, fontFamily: 'MaterialIcons');
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
      final expense = await firestore.getCategories('expense');
      final income = await firestore.getCategories('income');
      
      // Load all transactions to count category usage frequency
      List<TransactionModel> txns = [];
      try {
        txns = await firestore.getAllTransactions();
      } catch (e) {
        debugPrint('⚠️ Error fetching transactions for sorting categories: $e');
      }

      // Count usage frequency of each category name
      final usageCounts = <String, int>{};
      for (final txn in txns) {
        final catName = txn.category;
        usageCounts[catName] = (usageCounts[catName] ?? 0) + 1;
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

      sortCategories(expense);
      sortCategories(income);

      if (mounted) {
        setState(() {
          _expenseCategories = expense;
          _incomeCategories = income;
          _loadingCategories = false;

          // If editing, match category by name
          if (_isEditing && _selectedCategoryName != null) {
            final cats = _typeIndex == 0 ? expense : income;
            for (final c in cats) {
              if (c.name == _selectedCategoryName) {
                _selectedCategoryIcon = c.icon;
                break;
              }
            }
          } else {
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
        return Container(
          height: 320,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        style: TextStyle(color: Colors.grey.shade600),
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
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
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
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
              child: Row(
                children: [
                  _buildCloseButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit Transaction' : 'New Transaction',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Type Toggle ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTypeToggle(),
            ),
            const SizedBox(height: 16),

            // ── Scrollable Content ──
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: bottomInset + 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Amount Card ──
                    _buildAmountCard(),
                    const SizedBox(height: 16),

                    // ── Category Section ──
                    _buildSectionLabel('Category'),
                    const SizedBox(height: 10),
                    _buildCategorySearch(),
                    const SizedBox(height: 12),
                    _buildCategoryGrid(),
                    const SizedBox(height: 20),

                    // ── Note ──
                    _buildSectionLabel('Note (optional)'),
                    const SizedBox(height: 10),
                    _buildNoteField(),
                    const SizedBox(height: 16),

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
              _categoryQuery = '';
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
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(20),
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
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
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
                    fontWeight: FontWeight.w700,
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
                      fontSize: 42,
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
                        fontSize: 42,
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

  Widget _buildCategorySearch() {
    return TextField(
      onChanged: (v) => setState(() => _categoryQuery = v.trim()),
      style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search categories...',
        hintStyle: TextStyle(
          color: AppColors.textLightOf(context),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: AppColors.textLightOf(context),
          size: 20,
        ),
        suffixIcon: _categoryQuery.isNotEmpty
            ? GestureDetector(
                onTap: () => setState(() => _categoryQuery = ''),
                child: Icon(Icons.close_rounded, color: AppColors.textSecondaryOf(context), size: 18),
              )
            : null,
        filled: true,
        fillColor: AppColors.cardOf(context),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    if (_loadingCategories) {
      return _buildCategoryShimmer();
    }

    final filtered = _currentCategories.where((c) {
      if (_categoryQuery.isEmpty) return true;
      return c.name.toLowerCase().contains(_categoryQuery.toLowerCase());
    }).toList();

    if (filtered.isEmpty && _categoryQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded, size: 32, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                'No categories found',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double spacing = 10.0;
        const int crossAxisCount = 2;
        const double totalSpacing = spacing * (crossAxisCount - 1);
        final double itemWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            ...filtered.map((c) => SizedBox(
                  width: itemWidth,
                  child: _buildCategoryChip(c),
                )),
            SizedBox(
              width: itemWidth,
              child: _buildAddCategoryChip(),
            ),
          ],
        );
      },
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
        duration: const Duration(milliseconds: 200),
        height: 64,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? catColor
              : catColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? catColor : catColor.withValues(alpha: 0.15),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: catColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.01),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(right: 32.0),
                child: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : catColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  category.icon,
                  size: 16,
                  color: isSelected ? Colors.white : catColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddCategoryChip() {
    return GestureDetector(
      onTap: () => _showCreateCategory(context),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add New',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            8,
            (_) => Container(
              width: itemWidth,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
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
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
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
    final iconCodePoint = _selectedCategoryIcon?.codePoint ?? Icons.note_rounded.codePoint;

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
        _showSuccess('Transaction updated!');
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
        _showSuccess('Transaction saved!');
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
    IconData? pickedIcon;

    final icons = _iconChoices;

    final result = await showModalBottomSheet<cat.Category>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            'New Category',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Category Name',
                          hintText: 'e.g., Starbucks',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Pick an icon',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: GridView.builder(
                          controller: scrollController,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: icons.length,
                          itemBuilder: (c, i) {
                            final ic = icons[i];
                            final selected = pickedIcon == ic;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setModalState(() => pickedIcon = ic);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.primary.withValues(alpha: 0.15)
                                      : Colors.grey.shade50,
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.grey.shade200,
                                    width: selected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  ic,
                                  color: selected
                                      ? AppColors.secondary
                                      : Colors.grey.shade700,
                                  size: 22,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (nameCtrl.text.trim().isEmpty || pickedIcon == null) {
                              return;
                            }
                            final name = nameCtrl.text.trim();
                            final newCat = cat.Category(
                              id: '',
                              name: name,
                              icon: pickedIcon!,
                              color: AppColors.getCategoryColor(name),
                              type: _typeIndex == 0 ? 'expense' : 'income',
                              order: _currentCategories.length,
                            );

                            try {
                              final id = await FirestoreService.instance.addCategory(newCat);
                              if (!ctx.mounted) return;
                              Navigator.of(ctx).pop(newCat.copyWith(id: id));
                            } catch (e) {
                              debugPrint('❌ Error adding category: $e');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Create Category',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
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
        Icons.note_rounded,
      ];

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.expense,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.income,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 800),
      ),
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
