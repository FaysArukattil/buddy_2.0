import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

class PdfService {
  /// Generate PDF for a single transaction
  static Future<File> generateSingleTransactionPdf(
    Map<String, dynamic> transaction,
  ) async {
    final pdf = pw.Document();

    // Format data
    final amount = (transaction['amount'] as num).toDouble();
    final type = transaction['type'] as String;

    // Handle date - can be String or DateTime
    final DateTime date;
    if (transaction['date'] is String) {
      date = DateTime.parse(transaction['date'] as String);
    } else if (transaction['date'] is DateTime) {
      date = transaction['date'] as DateTime;
    } else {
      date = DateTime.now();
    }

    final category = transaction['category'] as String;
    final note = transaction['note'] as String? ?? 'No note';

    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('hh:mm a');
    final currencyFormat = NumberFormat.currency(
      symbol: 'Rs. ',
      decimalDigits: 2,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: type.toLowerCase() == 'expense'
                      ? PdfColor.fromHex('#FF6B6B')
                      : PdfColor.fromHex('#4CAF50'),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Transaction Receipt',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Buddy Expense Tracker',
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 30),

              // Transaction Details
              pw.Text(
                'Transaction Details',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 15),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 15),

              // Amount
              _buildDetailRow('Amount', currencyFormat.format(amount)),
              pw.SizedBox(height: 10),

              // Type
              _buildDetailRow('Type', type.toUpperCase()),
              pw.SizedBox(height: 10),

              // Category
              _buildDetailRow('Category', category),
              pw.SizedBox(height: 10),

              // Date
              _buildDetailRow('Date', dateFormat.format(date)),
              pw.SizedBox(height: 10),

              // Time
              _buildDetailRow('Time', timeFormat.format(date)),
              pw.SizedBox(height: 10),

              // Note
              pw.SizedBox(height: 20),
              pw.Text(
                'Note:',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Text(note, style: const pw.TextStyle(fontSize: 12)),
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text(
                'Generated on ${DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
            ],
          );
        },
      ),
    );

    return _savePdf(
      pdf,
      'transaction_${transaction['id']}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  /// Generate PDF for multiple transactions with comprehensive analytical data:
  /// - Executive Financial Overview (Income, Expense, Net Balance, Savings Rate)
  /// - Key Analytical Insights (Average spend, highest expense, transaction split)
  /// - Top Spending Categories Breakdown with share % and visual progress indicators
  /// - Income Sources Breakdown
  /// - Itemized Transaction History with descriptions and status badges
  static Future<File> generateMultipleTransactionsPdf({
    required List<Map<String, dynamic>> transactions,
    required String title,
    String? subtitle,
  }) async {
    final pdf = pw.Document();

    final currencyFormat = NumberFormat.currency(
      symbol: 'Rs. ',
      decimalDigits: 2,
    );
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('hh:mm a');

    // ── 1. Calculate Core Financial Metrics ──
    double totalIncome = 0;
    double totalExpense = 0;
    int expenseCount = 0;
    int incomeCount = 0;

    Map<String, dynamic>? maxExpenseTxn;
    Map<String, dynamic>? maxIncomeTxn;

    final expenseByCategory = <String, double>{};
    final expenseCountByCategory = <String, int>{};
    final incomeByCategory = <String, double>{};
    final incomeCountByCategory = <String, int>{};

    for (final t in transactions) {
      final amount = (t['amount'] as num).toDouble();
      final type = (t['type'] as String).toLowerCase().trim();
      final category = (t['category'] as String?)?.trim() ?? 'Other';

      if (type == 'income') {
        totalIncome += amount;
        incomeCount++;
        incomeByCategory[category] = (incomeByCategory[category] ?? 0) + amount;
        incomeCountByCategory[category] =
            (incomeCountByCategory[category] ?? 0) + 1;

        if (maxIncomeTxn == null ||
            amount > (maxIncomeTxn['amount'] as num).toDouble()) {
          maxIncomeTxn = t;
        }
      } else {
        totalExpense += amount;
        expenseCount++;
        expenseByCategory[category] =
            (expenseByCategory[category] ?? 0) + amount;
        expenseCountByCategory[category] =
            (expenseCountByCategory[category] ?? 0) + 1;

        if (maxExpenseTxn == null ||
            amount > (maxExpenseTxn['amount'] as num).toDouble()) {
          maxExpenseTxn = t;
        }
      }
    }

    final netBalance = totalIncome - totalExpense;
    final savingsRate = totalIncome > 0
        ? ((netBalance / totalIncome) * 100).clamp(-100.0, 100.0)
        : null;
    final avgExpensePerTxn =
        expenseCount > 0 ? (totalExpense / expenseCount) : 0.0;

    // Sort categories descending
    final sortedExpenses = expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedIncomes = incomeByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Sort transactions chronologically (newest first)
    final sortedTxns = List<Map<String, dynamic>>.from(transactions)
      ..sort((a, b) {
        DateTime da = _parseDate(a['date']);
        DateTime db = _parseDate(b['date']);
        return db.compareTo(da);
      });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Buddy Expense Tracker | Financial Analytics & Report',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            // ── Executive Header ──
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  colors: [
                    PdfColor.fromHex('#1E3A8A'),
                    PdfColor.fromHex('#0D9488'),
                  ],
                ),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        title,
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      if (subtitle != null) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          subtitle,
                          style: const pw.TextStyle(
                            fontSize: 13,
                            color: PdfColors.white,
                          ),
                        ),
                      ],
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Buddy Expense Tracker | Executive Financial Report',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey200,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Generated',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey200,
                        ),
                      ),
                      pw.Text(
                        dateFormat.format(DateTime.now()),
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.Text(
                        timeFormat.format(DateTime.now()),
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey200,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 18),

            // ── Executive Summary Cards (Row of 4) ──
            pw.Row(
              children: [
                pw.Expanded(
                  child: _buildSummaryCard(
                    'TOTAL INCOME',
                    currencyFormat.format(totalIncome),
                    PdfColor.fromHex('#059669'),
                    '$incomeCount transaction${incomeCount == 1 ? "" : "s"}',
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildSummaryCard(
                    'TOTAL EXPENSE',
                    currencyFormat.format(totalExpense),
                    PdfColor.fromHex('#DC2626'),
                    '$expenseCount transaction${expenseCount == 1 ? "" : "s"}',
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildSummaryCard(
                    'NET BALANCE',
                    '${netBalance >= 0 ? "+" : ""}${currencyFormat.format(netBalance)}',
                    netBalance >= 0
                        ? PdfColor.fromHex('#2563EB')
                        : PdfColor.fromHex('#DC2626'),
                    netBalance >= 0 ? 'Net Positive' : 'Deficit',
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _buildSummaryCard(
                    'SAVINGS RATE',
                    savingsRate != null
                        ? '${savingsRate.toStringAsFixed(1)}%'
                        : 'N/A',
                    savingsRate != null && savingsRate >= 0
                        ? PdfColor.fromHex('#7C3AED')
                        : PdfColor.fromHex('#D97706'),
                    totalIncome > 0
                        ? 'of total income'
                        : 'No income logged',
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 18),

            // ── Key Analytical Insights Highlight Box ──
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(
                  color: PdfColor.fromHex('#E2E8F0'),
                  width: 1,
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ANALYTICAL HIGHLIGHTS & INSIGHTS',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#475569'),
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildInsightItem(
                          'Average Spend / Txn',
                          currencyFormat.format(avgExpensePerTxn),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildInsightItem(
                          'Total Records Logged',
                          '${transactions.length} ($expenseCount exp, $incomeCount inc)',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildInsightItem(
                          'Highest Expense',
                          maxExpenseTxn != null
                              ? '${currencyFormat.format((maxExpenseTxn['amount'] as num).toDouble())} - ${maxExpenseTxn['category']}'
                              : 'None',
                        ),
                      ),
                      if (maxIncomeTxn != null)
                        pw.Expanded(
                          child: _buildInsightItem(
                            'Highest Income',
                            '${currencyFormat.format((maxIncomeTxn['amount'] as num).toDouble())} - ${maxIncomeTxn['category']}',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // ── Top Spending Categories Section ──
            pw.Text(
              'TOP SPENDING CATEGORIES BREAKDOWN',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1E293B'),
                letterSpacing: 0.3,
              ),
            ),
            pw.SizedBox(height: 8),

            if (sortedExpenses.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#F8FAFC'),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  'No expenses recorded for this period.',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColor.fromHex('#E2E8F0'),
                  width: 0.8,
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(40),
                  1: pw.FlexColumnWidth(3),
                  2: pw.FixedColumnWidth(80),
                  3: pw.FixedColumnWidth(95),
                  4: pw.FixedColumnWidth(70),
                  5: pw.FlexColumnWidth(2.5),
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F1F5F9'),
                    ),
                    children: [
                      _buildTableCell('#', isHeader: true),
                      _buildTableCell('Category', isHeader: true),
                      _buildTableCell('Txns', isHeader: true),
                      _buildTableCell('Amount', isHeader: true),
                      _buildTableCell('Share %', isHeader: true),
                      _buildTableCell('Visual Share', isHeader: true),
                    ],
                  ),
                  // Category Rows
                  ...sortedExpenses.asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final catName = entry.value.key;
                    final catAmt = entry.value.value;
                    final catCount = expenseCountByCategory[catName] ?? 1;
                    final pct = totalExpense > 0
                        ? (catAmt / totalExpense * 100)
                        : 0.0;
                    final isEven = rank % 2 == 0;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: isEven
                            ? PdfColor.fromHex('#F8FAFC')
                            : PdfColors.white,
                      ),
                      children: [
                        _buildTableCell('$rank'),
                        _buildTableCell(catName),
                        _buildTableCell('$catCount txns'),
                        _buildTableCell(
                          currencyFormat.format(catAmt),
                          color: PdfColor.fromHex('#DC2626'),
                        ),
                        _buildTableCell('${pct.toStringAsFixed(1)}%'),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 7,
                          ),
                          child: pw.Stack(
                            children: [
                              pw.Container(
                                height: 6,
                                decoration: pw.BoxDecoration(
                                  color: PdfColor.fromHex('#E2E8F0'),
                                  borderRadius: pw.BorderRadius.circular(3),
                                ),
                              ),
                              pw.Container(
                                width: (pct * 0.9).clamp(2.0, 90.0),
                                height: 6,
                                decoration: pw.BoxDecoration(
                                  color: PdfColor.fromHex('#DC2626'),
                                  borderRadius: pw.BorderRadius.circular(3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),

            // ── Income Breakdown (if any income) ──
            if (sortedIncomes.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text(
                'INCOME SOURCES BREAKDOWN',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1E293B'),
                  letterSpacing: 0.3,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColor.fromHex('#E2E8F0'),
                  width: 0.8,
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(40),
                  1: pw.FlexColumnWidth(3),
                  2: pw.FixedColumnWidth(80),
                  3: pw.FixedColumnWidth(95),
                  4: pw.FixedColumnWidth(70),
                  5: pw.FlexColumnWidth(2.5),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F1F5F9'),
                    ),
                    children: [
                      _buildTableCell('#', isHeader: true),
                      _buildTableCell('Source', isHeader: true),
                      _buildTableCell('Txns', isHeader: true),
                      _buildTableCell('Amount', isHeader: true),
                      _buildTableCell('Share %', isHeader: true),
                      _buildTableCell('Visual Share', isHeader: true),
                    ],
                  ),
                  ...sortedIncomes.asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final catName = entry.value.key;
                    final catAmt = entry.value.value;
                    final catCount = incomeCountByCategory[catName] ?? 1;
                    final pct = totalIncome > 0
                        ? (catAmt / totalIncome * 100)
                        : 0.0;
                    final isEven = rank % 2 == 0;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: isEven
                            ? PdfColor.fromHex('#F8FAFC')
                            : PdfColors.white,
                      ),
                      children: [
                        _buildTableCell('$rank'),
                        _buildTableCell(catName),
                        _buildTableCell('$catCount txns'),
                        _buildTableCell(
                          currencyFormat.format(catAmt),
                          color: PdfColor.fromHex('#059669'),
                        ),
                        _buildTableCell('${pct.toStringAsFixed(1)}%'),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 7,
                          ),
                          child: pw.Stack(
                            children: [
                              pw.Container(
                                height: 6,
                                decoration: pw.BoxDecoration(
                                  color: PdfColor.fromHex('#E2E8F0'),
                                  borderRadius: pw.BorderRadius.circular(3),
                                ),
                              ),
                              pw.Container(
                                width: (pct * 0.9).clamp(2.0, 90.0),
                                height: 6,
                                decoration: pw.BoxDecoration(
                                  color: PdfColor.fromHex('#059669'),
                                  borderRadius: pw.BorderRadius.circular(3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],

            pw.SizedBox(height: 22),

            // ── Itemized Transactions Log Table ──
            pw.Text(
              'ITEMIZED TRANSACTIONS LOG (${transactions.length})',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1E293B'),
                letterSpacing: 0.3,
              ),
            ),
            pw.SizedBox(height: 8),

            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColor.fromHex('#E2E8F0'),
                width: 0.8,
              ),
              columnWidths: const {
                0: pw.FixedColumnWidth(85),
                1: pw.FixedColumnWidth(95),
                2: pw.FlexColumnWidth(3),
                3: pw.FixedColumnWidth(65),
                4: pw.FixedColumnWidth(85),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F1F5F9'),
                  ),
                  children: [
                    _buildTableCell('Date', isHeader: true),
                    _buildTableCell('Category', isHeader: true),
                    _buildTableCell('Note / Description', isHeader: true),
                    _buildTableCell('Type', isHeader: true),
                    _buildTableCell('Amount', isHeader: true),
                  ],
                ),
                ...sortedTxns.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final t = entry.value;
                  final dt = _parseDate(t['date']);
                  final amt = (t['amount'] as num).toDouble();
                  final type = (t['type'] as String).toLowerCase().trim();
                  final isIncome = type == 'income';
                  final note = (t['note'] as String?)?.trim();
                  final category =
                      (t['category'] as String?)?.trim() ?? 'Other';
                  final isEven = idx % 2 == 0;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: isEven
                          ? PdfColor.fromHex('#F8FAFC')
                          : PdfColors.white,
                    ),
                    children: [
                      _buildTableCell(dateFormat.format(dt)),
                      _buildTableCell(category),
                      _buildTableCell(
                        note != null && note.isNotEmpty ? note : '—',
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: pw.BoxDecoration(
                            color: isIncome
                                ? PdfColor.fromHex('#ECFDF5')
                                : PdfColor.fromHex('#FEF2F2'),
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(
                              color: isIncome
                                  ? PdfColor.fromHex('#A7F3D0')
                                  : PdfColor.fromHex('#FECACA'),
                              width: 0.6,
                            ),
                          ),
                          child: pw.Center(
                            child: pw.Text(
                              isIncome ? 'INCOME' : 'EXPENSE',
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                color: isIncome
                                    ? PdfColor.fromHex('#047857')
                                    : PdfColor.fromHex('#B91C1C'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _buildTableCell(
                        '${isIncome ? "+" : "-"}${currencyFormat.format(amt)}',
                        color: isIncome
                            ? PdfColor.fromHex('#059669')
                            : PdfColor.fromHex('#DC2626'),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    final fileName =
        '${title.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    return _savePdf(pdf, fileName);
  }

  /// Helper: Parse date from dynamic value (DateTime, String, or Timestamp)
  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  /// Helper: Build executive summary card
  static pw.Widget _buildSummaryCard(
    String label,
    String value,
    PdfColor color, [
    String? subtitle,
  ]) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: pw.BoxDecoration(
        color: color.shade(0.08),
        border: pw.Border.all(color: color, width: 1.2),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.5,
              color: color,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 12.5,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              subtitle,
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Helper: Build insight item
  static pw.Widget _buildInsightItem(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(right: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#0F172A'),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Build detail row
  static pw.Widget _buildDetailRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(value, style: const pw.TextStyle(fontSize: 14)),
      ],
    );
  }

  /// Helper: Build table cell
  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 9.5 : 8.5,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? (isHeader ? PdfColors.black : PdfColor.fromHex('#334155')),
        ),
      ),
    );
  }

  /// Save PDF to device
  static Future<File> _savePdf(pw.Document pdf, String fileName) async {
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Open PDF file
  static Future<void> openPdf(File file) async {
    await OpenFile.open(file.path);
  }

  /// Share PDF file
  static Future<void> sharePdf(File file) async {
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: file.path.split('/').last,
    );
  }

  /// Print PDF
  static Future<void> printPdf(File file) async {
    await Printing.layoutPdf(
      onLayout: (format) async => await file.readAsBytes(),
    );
  }
}
