import 'package:flutter/material.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/widgets/animated_money_text.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/views/screens/add_transaction_screen.dart';
import 'package:buddy/services/pdf_service.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const TransactionDetailScreen({super.key, required this.data});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool _isDownloading = false;

  bool get _isIncome => (widget.data['type'] as String).toLowerCase().trim() == 'income';

  @override
  Widget build(BuildContext context) {
    final Color accent = _isIncome ? AppColors.income : AppColors.expense;
    final String category = (widget.data['category'] as String?) ?? 'Other';
    final Color catColor = AppColors.getCategoryColor(category);

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            width: double.infinity,
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
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Download PDF Statement',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Premium Header (Dark text on white background)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade100,
                          width: 1.5,
                        ),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Transaction Details',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _openEdit,
                        icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                      ),
                      IconButton(
                        onPressed: _confirmDelete,
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      
                      // Custom Card containing Title/Category and dynamic colored icon
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade100, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            // Beautiful brand-color coordinated icon container
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: widget.data['icon'] != null
                                  ? Icon(
                                      IconData(
                                        widget.data['icon'] as int, // ignore: non_const_argument_for_const_parameter
                                        fontFamily: 'MaterialIcons',
                                      ),
                                      size: 24,
                                      color: catColor,
                                    )
                                  : Center(child: _avatarChild(widget.data)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: accent.withValues(alpha: 0.15),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          _isIncome ? 'Income' : 'Expense',
                                          style: TextStyle(
                                            color: accent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (widget.data['title'] as String?) ?? 'Transaction',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Details list card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade100, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TRANSACTION DETAIL',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _detailRow(
                              'Category',
                              category,
                              isBold: true,
                            ),
                            const Divider(height: 20, color: Color(0xFFF1F1F1)),
                            _detailRow(
                              'Time',
                              (widget.data['time'] as String?) ?? '-',
                            ),
                            const Divider(height: 20, color: Color(0xFFF1F1F1)),
                            _detailRow(
                              'Date',
                              _formatDate(
                                (widget.data['date'] as DateTime?) ?? DateTime.now(),
                              ),
                            ),
                            const Divider(height: 20, color: Color(0xFFF1F1F1)),
                            _detailRow(
                              'Note',
                              (widget.data['note'] as String?)?.trim().isNotEmpty == true
                                  ? widget.data['note'] as String
                                  : '-',
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: Column(
                                children: [
                                  Text(
                                    'AMOUNT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade400,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  AnimatedMoneyText(
                                    value: (widget.data['amount'] as double?) ?? 0,
                                    showSign: true,
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      color: _isIncome ? AppColors.income : AppColors.textPrimary,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 40),
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

  Widget _avatarChild(Map<String, dynamic> data) {
    final String text = (data['avatarText'] as String? ?? '?').toUpperCase();
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppColors.secondary,
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
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

  Future<void> _downloadPdf() async {
    setState(() => _isDownloading = true);
    
    try {
      // Generate PDF
      final file = await PdfService.generateSingleTransactionPdf(widget.data);
      
      if (!mounted) return;
      
      // Show options dialog
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PDF Generated Successfully!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.open_in_new, color: AppColors.primary),
                title: const Text('Open PDF'),
                onTap: () {
                  Navigator.pop(context);
                  PdfService.openPdf(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: AppColors.secondary),
                title: const Text('Share PDF'),
                onTap: () {
                  Navigator.pop(context);
                  PdfService.sharePdf(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.print, color: AppColors.income),
                title: const Text('Print PDF'),
                onTap: () {
                  Navigator.pop(context);
                  PdfService.printPdf(file);
                },
              ),
            ],
          ),
        ),
      );
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
        title: const Text('Delete transaction?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
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
