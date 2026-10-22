import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/icon_helper.dart';
import 'package:buddy/views/widgets/animated_money_text.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/views/screens/add_transaction_screen.dart';
import 'package:buddy/services/pdf_service.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const TransactionDetailScreen({super.key, required this.data});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool _isDownloading = false;

  bool get _isIncome =>
      (widget.data['type'] as String).toLowerCase().trim() == 'income';

  DateTime get _parsedDate {
    final raw = widget.data['date'];
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  double get _parsedAmount {
    final raw = widget.data['amount'];
    if (raw is num) return raw.toDouble();
    return 0.0;
  }

  String? get _note {
    final raw = (widget.data['note'] as String?)?.trim();
    return TransactionModel.cleanNoteText(raw);
  }
  String get _category =>
      (widget.data['category'] as String?)?.trim() ?? 'Other';

  String get _title {
    if (_note != null && _note!.isNotEmpty) return _note!;
    final customTitle = (widget.data['title'] as String?)?.trim();
    final cleanTitle = TransactionModel.cleanNoteText(customTitle);
    if (cleanTitle != null && cleanTitle.isNotEmpty) return cleanTitle;
    return _category;
  }

  bool get _isAutoDetected =>
      widget.data['auto_detected'] == true || widget.data['autoDetected'] == true;

  String? get _source => widget.data['notificationSource'] as String?;

  String _formatTime(DateTime d) {
    final hour = d.hour;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $ampm';
  }

  String _formatFullDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dayName = days[dt.weekday - 1];
    return '$dayName, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _isIncome ? AppColors.income : AppColors.expense;
    final Color catColor = AppColors.getCategoryColor(_category);
    final dt = _parsedDate;
    final rawId = widget.data['id'] as String?;
    final shortId = (rawId != null && rawId.isNotEmpty)
        ? rawId.substring(0, math.min(10, rawId.length)).toUpperCase()
        : null;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Center(
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textPrimaryOf(context),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Transaction Details',
          style: TextStyle(
            color: AppColors.textPrimaryOf(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          // Edit Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: InkWell(
              onTap: _openEdit,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.cardOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.edit_outlined,
                  color: AppColors.textPrimaryOf(context),
                  size: 19,
                ),
              ),
            ),
          ),
          // Delete Button
          Padding(
            padding: const EdgeInsets.only(right: 14.0, left: 4.0),
            child: InkWell(
              onTap: _confirmDelete,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.expense.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.expense.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.expense,
                  size: 19,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── LUXURY FINTECH DIGITAL RECEIPT CARD ──
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardOf(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: AppColors.cardShadowOf(context),
                ),
                child: Column(
                  children: [
                    // Top Receipt Header & Category Branding
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(
                        children: [
                          // Category Avatar with soft glow
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: catColor.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              IconHelper.getIcon(widget.data['icon']),
                              color: catColor,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Transaction Title
                          Text(
                            _title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimaryOf(context),
                              letterSpacing: -0.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),

                          // Pill Badges Row (Category + Type + Auto)
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              // Category badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: catColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _category,
                                  style: TextStyle(
                                    color: catColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),

                              // Type badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isIncome
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      size: 13,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isIncome ? 'Income' : 'Expense',
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (_isAutoDetected)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF6366F1),
                                        Color(0xFF8B5CF6),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1)
                                            .withValues(alpha: 0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'AI Auto-Detected',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Large Hero Amount Display
                          Text(
                            'AMOUNT',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textLightOf(context),
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedMoneyText(
                            value: _parsedAmount,
                            showSign: true,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: _isIncome
                                  ? AppColors.income
                                  : AppColors.expense,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Status indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1EBE5D)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 13,
                                  color: Color(0xFF1EBE5D),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Recorded in Buddy',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1EBE5D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Receipt Perforated Dotted Divider
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // Left half-circle cut
                          Container(
                            width: 14,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.backgroundOf(context),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(14),
                                bottomRight: Radius.circular(14),
                              ),
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final boxWidth = constraints.constrainWidth();
                                const dashWidth = 5.0;
                                const dashSpace = 4.0;
                                final dashCount =
                                    (boxWidth / (dashWidth + dashSpace)).floor();
                                return Flex(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  direction: Axis.horizontal,
                                  children: List.generate(dashCount, (_) {
                                    return SizedBox(
                                      width: dashWidth,
                                      height: 1.2,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: AppColors.borderOf(context),
                                        ),
                                      ),
                                    );
                                  }),
                                );
                              },
                            ),
                          ),
                          // Right half-circle cut
                          Container(
                            width: 14,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.backgroundOf(context),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(14),
                                bottomLeft: Radius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Receipt Itemized Details Table
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            icon: Icons.calendar_today_rounded,
                            label: 'Date',
                            value: _formatFullDate(dt),
                          ),
                          Divider(
                            height: 22,
                            color: AppColors.borderOf(context).withValues(alpha: 0.5),
                          ),
                          _buildDetailRow(
                            icon: Icons.access_time_rounded,
                            label: 'Time',
                            value: _formatTime(dt),
                          ),
                          Divider(
                            height: 22,
                            color: AppColors.borderOf(context).withValues(alpha: 0.5),
                          ),
                          _buildDetailRow(
                            icon: Icons.category_rounded,
                            label: 'Category',
                            value: _category,
                            valueColor: catColor,
                            isBold: true,
                          ),
                          Divider(
                            height: 22,
                            color: AppColors.borderOf(context).withValues(alpha: 0.5),
                          ),
                          _buildDetailRow(
                            icon: Icons.input_rounded,
                            label: 'Entry Source',
                            value: _isAutoDetected
                                ? (_source != null && _source!.isNotEmpty
                                    ? 'Auto ($sourceClean)'
                                    : 'Bank SMS Notification')
                                : 'Manual Entry',
                          ),
                          if (shortId != null) ...[
                            Divider(
                              height: 22,
                              color: AppColors.borderOf(context).withValues(alpha: 0.5),
                            ),
                            _buildDetailRow(
                              icon: Icons.tag_rounded,
                              label: 'Transaction ID',
                              value: '#$shortId',
                              trailing: InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: rawId!));
                                  HapticFeedback.selectionClick();
                                  AppSnackbar.showSuccess(
                                    context,
                                    'Transaction ID copied to clipboard',
                                  );
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.copy_rounded,
                                    size: 15,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ),
                            ),
                          ],

                          // Dedicated Note Box
                          if (_note != null && _note!.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
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
                                    children: [
                                      Icon(
                                        Icons.sticky_note_2_rounded,
                                        size: 14,
                                        color: AppColors.textSecondaryOf(context),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'NOTES / REMARKS',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textSecondaryOf(context),
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _note!,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: AppColors.textPrimaryOf(context),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── PRIMARY ACTION: DOWNLOAD STATEMENT / PDF RECEIPT ──
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: AppColors.primary.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _isDownloading ? null : _downloadPdf,
                  child: _isDownloading
                      ? const BuddyLoadingIndicator(size: 24)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.picture_as_pdf_rounded, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Download PDF Receipt',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // ── SECONDARY ACTIONS: EDIT / DELETE ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: AppColors.borderOf(context),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _openEdit,
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.textPrimaryOf(context),
                      ),
                      label: Text(
                        'Edit',
                        style: TextStyle(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: AppColors.expense.withValues(alpha: 0.3),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _confirmDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppColors.expense,
                      ),
                      label: const Text(
                        'Delete',
                        style: TextStyle(
                          color: AppColors.expense,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
  }

  String get sourceClean {
    if (_source == null) return '';
    return _source!.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '');
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: AppColors.textSecondaryOf(context),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondaryOf(context),
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimaryOf(context),
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing,
        ],
      ],
    );
  }

  Future<void> _downloadPdf() async {
    setState(() => _isDownloading = true);

    try {
      final file = await PdfService.generateSingleTransactionPdf(widget.data);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: BoxDecoration(
            color: AppColors.cardOf(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'PDF Receipt Ready',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryOf(ctx),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how you want to handle your statement',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondaryOf(ctx),
                ),
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.open_in_new_rounded, color: AppColors.primary, size: 20),
                ),
                title: Text(
                  'Open PDF',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(ctx),
                  ),
                ),
                subtitle: Text(
                  'View statement on your device',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(ctx),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  PdfService.openPdf(file);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.share_rounded, color: AppColors.secondary, size: 20),
                ),
                title: Text(
                  'Share PDF',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(ctx),
                  ),
                ),
                subtitle: Text(
                  'Send via WhatsApp, Mail, or AirDrop',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(ctx),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  PdfService.sharePdf(file);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.income.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.print_rounded, color: AppColors.income, size: 20),
                ),
                title: Text(
                  'Print PDF',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(ctx),
                  ),
                ),
                subtitle: Text(
                  'Send to wireless printer',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(ctx),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  PdfService.printPdf(file);
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Error generating PDF: $e');
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _openEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(existingTransaction: widget.data),
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _confirmDelete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Delete transaction?',
          style: TextStyle(
            color: AppColors.textPrimaryOf(ctx),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this transaction? This action cannot be undone.',
          style: TextStyle(
            color: AppColors.textSecondaryOf(ctx),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondaryOf(ctx)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.expense,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final id = widget.data['id'];
    if (id is String && id.isNotEmpty) {
      await FirestoreService.instance.deleteTransaction(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }
}
