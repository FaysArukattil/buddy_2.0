import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/repositories/transaction_repository.dart';

class AddTransactionScreen extends StatefulWidget {
  final Map<String, dynamic>? existingTransaction;

  const AddTransactionScreen({super.key, this.existingTransaction});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen>
    with SingleTickerProviderStateMixin {
  int _typeIndex = 0;
  double _page = 0;
  bool _dragging = false;
  double _dragIndicatorPage = 0;
  double _dragStartPage = 0;
  double _dragAccumX = 0;
  bool _showCategories = false;
  String _categoryQuery = '';

  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  _CategoryOption? _selectedCategory;
  DateTime _selectedDate = DateTime.now();

  late final AnimationController _bobController;
  late final Animation<double> _bobAnimation;

  late final List<_CategoryOption> _defaultExpenseCategories = [
    _CategoryOption('Food', Icons.restaurant_rounded),
    _CategoryOption('Icecream', Icons.icecream_rounded),
    _CategoryOption('Sweets', Icons.cake_rounded),
    _CategoryOption('Fuel', Icons.local_gas_station_rounded),
    _CategoryOption('Netflix', Icons.movie_rounded),
    _CategoryOption('Youtube', Icons.ondemand_video_rounded),
    _CategoryOption('Hotstar', Icons.live_tv_rounded),
    _CategoryOption('Gym', Icons.fitness_center_rounded),
    _CategoryOption('Charity', Icons.volunteer_activism_rounded),
    _CategoryOption('Friends', Icons.handshake_rounded),
    _CategoryOption('Travel', Icons.flight_rounded),
    _CategoryOption('Party', Icons.celebration_rounded),
  ];

  late final List<_CategoryOption> _defaultIncomeCategories = [
    _CategoryOption('Salary', Icons.payments_rounded),
    _CategoryOption('Freelance', Icons.work_outline_rounded),
    _CategoryOption('Gift', Icons.card_giftcard_rounded),
    _CategoryOption('Interest', Icons.savings_rounded),
    _CategoryOption('Refund', Icons.reply_rounded),
  ];

  List<_CategoryOption> get _currentCategories =>
      _typeIndex == 0 ? _defaultExpenseCategories : _defaultIncomeCategories;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _bobAnimation = Tween<double>(
      begin: -6.0,
      end: 6.0,
    ).animate(CurvedAnimation(parent: _bobController, curve: Curves.easeInOut));
    _bobController.repeat(reverse: true);

    // Pre-fill if editing
    if (widget.existingTransaction != null) {
      final tx = widget.existingTransaction!;
      _amountController.text = (tx['amount'] as double).toStringAsFixed(2);
      _noteController.text = tx['note'] as String? ?? '';
      _selectedDate = tx['date'] as DateTime;
      final type = (tx['type'] as String).toLowerCase().trim();
      _typeIndex = type == 'income' ? 1 : 0;
      _page = _typeIndex.toDouble();

      // Find matching category
      final catName = tx['category'] as String;
      final iconCode = tx['icon'] as int?;
      final cats = type == 'income'
          ? _defaultIncomeCategories
          : _defaultExpenseCategories;
      _selectedCategory = cats.firstWhere(
        (c) => c.name == catName,
        orElse: () => iconCode != null
            ? _CategoryOption(
                catName,
                IconData(iconCode, fontFamily: 'MaterialIcons'),
              )
            : cats.first,
      );
    }
  }

  @override
  void dispose() {
    _bobController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    DateTime temp = _selectedDate;
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) {
        return Container(
          height: 300,
          color: Colors.white,
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() => _selectedDate = temp);
                      },
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  use24hFormat: false,
                  initialDateTime: _selectedDate,
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

  Future<_CategoryOption?> _showCreateCategory(BuildContext context) async {
    final TextEditingController nameCtrl = TextEditingController();
    IconData? pickedIcon;
    final icons = _iconChoices;

    return await showModalBottomSheet<_CategoryOption>(
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
              initialChildSize: 0.9,
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
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
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
                                setModalState(() {
                                  pickedIcon = ic;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.primary.withValues(
                                          alpha: 0.15,
                                        )
                                      : Colors.grey.shade50,
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.black12,
                                    width: selected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  ic,
                                  color: selected
                                      ? AppColors.secondary
                                      : Colors.black87,
                                  size: 24,
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
                          onPressed: () {
                            if (nameCtrl.text.trim().isEmpty ||
                                pickedIcon == null) {
                              Navigator.of(ctx).pop();
                              return;
                            }
                            Navigator.of(ctx).pop(
                              _CategoryOption(
                                nameCtrl.text.trim(),
                                pickedIcon!,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.88,
                            ),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Add Category',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
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
  }

  List<IconData> get _iconChoices => const [
    Icons.restaurant_rounded,
    Icons.icecream_rounded,
    Icons.cake_rounded,
    Icons.local_gas_station_rounded,
    Icons.movie_rounded,
    Icons.ondemand_video_rounded,
    Icons.live_tv_rounded,
    Icons.fitness_center_rounded,
    Icons.volunteer_activism_rounded,
    Icons.handshake_rounded,
    Icons.payments_rounded,
    Icons.work_outline_rounded,
    Icons.card_giftcard_rounded,
    Icons.savings_rounded,
    Icons.reply_rounded,
    Icons.shopping_bag_rounded,
    Icons.shopping_cart_rounded,
    Icons.pets_rounded,
    Icons.fastfood_rounded,
    Icons.medical_services_rounded,
    Icons.school_rounded,
    Icons.home_rounded,
    Icons.phone_android_rounded,
    Icons.subway_rounded,
    Icons.flight_rounded,
    Icons.local_taxi_rounded,
    Icons.sports_esports_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) {
          _dragAccumX = 0;
          setState(() {
            _dragging = true;
            _dragStartPage = _page;
            _dragIndicatorPage = _page;
          });
        },
        onHorizontalDragUpdate: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          final itemWidth = screenWidth / 2;
          _dragAccumX += details.delta.dx;
          final deltaPages = _dragAccumX / itemWidth;
          final double newPage = (_dragStartPage + deltaPages).clamp(0.0, 1.0);
          setState(() {
            _dragIndicatorPage = newPage;
          });
        },
        onHorizontalDragEnd: (details) {
          final target = _dragIndicatorPage.round();
          setState(() {
            _dragging = false;
            _page = target.toDouble();
            _typeIndex = target;
            _showCategories = false;
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topPadding),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.secondary.withValues(alpha: 0.24),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: const Icon(Icons.close_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.existingTransaction != null
                          ? 'Edit Transaction'
                          : 'Add Transaction',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  const itemCount = 2;
                  final itemWidth = totalWidth / itemCount;
                  final indicatorWidth = itemWidth - 12;
                  final animatedLeft =
                      (_dragging
                          ? (_dragIndicatorPage.clamp(0, itemCount - 1) *
                                itemWidth)
                          : (_page.clamp(0, itemCount - 1) * itemWidth)) +
                      6;

                  return Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.24),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: animatedLeft,
                          top: 4,
                          width: indicatorWidth,
                          height: 42,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOut,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.38),
                                  AppColors.secondary.withValues(alpha: 0.30),
                                ],
                              ),
                              border: Border.all(
                                color: AppColors.secondary.withValues(
                                  alpha: 0.35,
                                ),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  setState(() {
                                    _typeIndex = 0;
                                    _page = 0;
                                    _showCategories = false;
                                  });
                                },
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Expense',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            (((_dragging
                                                    ? _dragIndicatorPage
                                                    : _page)) <
                                                0.5)
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  setState(() {
                                    _typeIndex = 1;
                                    _page = 1;
                                    _showCategories = false;
                                  });
                                },
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Income',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            (((_dragging
                                                    ? _dragIndicatorPage
                                                    : _page)) >=
                                                0.5)
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white70, width: 1),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Amount',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              decoration: InputDecoration(
                                prefixIcon: Container(
                                  width: 40,
                                  alignment: Alignment.center,
                                  child: const Text(
                                    '₹',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 16,
                                ),
                                border: const OutlineInputBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Category',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _showCategories = !_showCategories;
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _showCategories
                                        ? AppColors.primary.withValues(
                                            alpha: 0.5,
                                          )
                                        : Colors.black26,
                                    width: _showCategories ? 2 : 1,
                                  ),
                                  color: _showCategories
                                      ? AppColors.primary.withValues(
                                          alpha: 0.05,
                                        )
                                      : Colors.transparent,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _selectedCategory != null
                                        ? Row(
                                            children: [
                                              Icon(
                                                _selectedCategory!.icon,
                                                size: 20,
                                                color: AppColors.secondary,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                _selectedCategory!.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            'Select a category',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 15,
                                            ),
                                          ),
                                    AnimatedRotation(
                                      turns: _showCategories ? 0.5 : 0,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _showCategories
                                  ? Column(
                                      children: [
                                        const SizedBox(height: 16),
                                        TextField(
                                          decoration: InputDecoration(
                                            hintText: 'Search categories',
                                            prefixIcon: const Icon(
                                              Icons.search_rounded,
                                              color: AppColors.primary,
                                            ),
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.3),
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: const BorderSide(
                                                color: AppColors.primary,
                                                width: 2,
                                              ),
                                            ),
                                            suffixIcon:
                                                _categoryQuery.isNotEmpty
                                                ? InkWell(
                                                    onTap: () => setState(
                                                      () => _categoryQuery = '',
                                                    ),
                                                    child: const Icon(
                                                      Icons.close_rounded,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          onChanged: (v) => setState(
                                            () => _categoryQuery = v.trim(),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _InlineCategoryGrid(
                                          current: _selectedCategory,
                                          options: (() {
                                            final list = _currentCategories
                                                .where(
                                                  (c) => c.name
                                                      .toLowerCase()
                                                      .contains(
                                                        _categoryQuery
                                                            .toLowerCase(),
                                                      ),
                                                )
                                                .toList();
                                            list.sort(
                                              (a, b) => a.name
                                                  .toLowerCase()
                                                  .compareTo(
                                                    b.name.toLowerCase(),
                                                  ),
                                            );
                                            return list;
                                          })(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                _selectedCategory = val;
                                                _showCategories = false;
                                                _categoryQuery = '';
                                              });
                                            }
                                          },
                                          onAddNew: (created) => setState(() {
                                            if (_typeIndex == 0) {
                                              _defaultExpenseCategories.add(
                                                created,
                                              );
                                            } else {
                                              _defaultIncomeCategories.add(
                                                created,
                                              );
                                            }
                                            _selectedCategory = created;
                                            _showCategories = false;
                                            _categoryQuery = '';
                                          }),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _noteController,
                              decoration: const InputDecoration(
                                labelText: 'Note',
                                hintText: 'Enter a name or note',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.black26),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Date',
                                      style: TextStyle(fontSize: 15),
                                    ),
                                    Text(
                                      _formatDate(_selectedDate),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      AnimatedBuilder(
                        animation: _bobAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _bobAnimation.value),
                            child: child,
                          );
                        },
                        child: SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _typeIndex == 0
                                  ? AppColors.expense.withValues(alpha: 0.88)
                                  : AppColors.income.withValues(alpha: 0.88),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 8,
                              shadowColor: const Color(0x33000000),
                            ),
                            onPressed: _saveTransaction,
                            child: Text(
                              _typeIndex == 0 ? 'Add Expense' : 'Add Income',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    final String amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      _showError('Please enter an amount');
      return;
    }
    final double? amount = double.tryParse(amountStr);
    if (amount == null) {
      _showError('Invalid amount');
      return;
    }
    if (amount == 0) {
      _showError('Amount cannot be zero');
      return;
    }
    if (_selectedCategory == null) {
      _showError('Please select a category');
      return;
    }

    final type = _typeIndex == 0 ? 'expense' : 'income';
    final category = _selectedCategory!.name;
    final iconCodePoint = _selectedCategory!.icon.codePoint;
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    final repo = TransactionRepository();
    try {
      if (widget.existingTransaction != null) {
        // Update existing
        final id = widget.existingTransaction!['id'] as int;
        final map = <String, Object?>{
          'amount': amount.abs(),
          'type': type,
          'date': _selectedDate.toIso8601String(),
          'note': note,
          'category': category,
          'icon': iconCodePoint,
        };
        await repo.update(id, map);
        if (!mounted) return;
        _showSuccess('Transaction updated successfully');
      } else {
        // Insert new
        await repo.add(
          amount: amount.abs(),
          type: type,
          date: _selectedDate,
          note: note,
          category: category,
          iconCodePoint: iconCodePoint,
        );
        if (!mounted) return;
        _showSuccess('Transaction saved successfully');
      }
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save transaction');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.expense,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.income,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = const [
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _CategoryOption {
  final String name;
  final IconData icon;
  _CategoryOption(this.name, this.icon);
}

class _InlineCategoryGrid extends StatelessWidget {
  final _CategoryOption? current;
  final List<_CategoryOption> options;
  final ValueChanged<_CategoryOption?> onChanged;
  final ValueChanged<_CategoryOption> onAddNew;
  const _InlineCategoryGrid({
    required this.current,
    required this.options,
    required this.onChanged,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _buildAddTile(context),
      ...options.map((opt) => _buildOption(context, opt)),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.start,
      children: tiles,
    );
  }

  Widget _buildAddTile(BuildContext context) {
    return InkWell(
      onTap: () async {
        final created = await context
            .findAncestorStateOfType<_AddTransactionScreenState>()
            ?._showCreateCategory(context);
        if (created != null) onAddNew(created);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 20, color: AppColors.primary),
            const SizedBox(width: 6),
            const Text(
              'Add New',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext context, _CategoryOption opt) {
    final selected = current?.name == opt.name;
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.15)
          : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(opt),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.primary : Colors.black26,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                opt.icon,
                size: 20,
                color: selected ? AppColors.secondary : Colors.black87,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  opt.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: selected ? AppColors.secondary : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
