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

  /// Generate PDF for multiple transactions (day, month, or custom range)
  static Future<File> generateMultipleTransactionsPdf({
    required List<Map<String, dynamic>> transactions,
    required String title,
    String? subtitle,
  }) async {
    final pdf = pw.Document();

    // Calculate totals
    double totalIncome = 0;
    double totalExpense = 0;

    for (var transaction in transactions) {
      final amount = (transaction['amount'] as num).toDouble();
      final type = (transaction['type'] as String).toLowerCase();

      if (type == 'income') {
        totalIncome += amount;
      } else if (type == 'expense') {
        totalExpense += amount;
      }
    }

    final balance = totalIncome - totalExpense;
    final currencyFormat = NumberFormat.currency(
      symbol: 'Rs. ',
      decimalDigits: 2,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  colors: [
                    PdfColor.fromHex('#6C63FF'),
                    PdfColor.fromHex('#4CAF50'),
                  ],
                ),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  if (subtitle != null) ...[
                    pw.SizedBox(height: 5),
                    pw.Text(
                      subtitle,
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
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

            pw.SizedBox(height: 20),

            // Summary Cards
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryCard(
                  'Total Income',
                  currencyFormat.format(totalIncome),
                  PdfColor.fromHex('#4CAF50'),
                ),
                _buildSummaryCard(
                  'Total Expense',
                  currencyFormat.format(totalExpense),
                  PdfColor.fromHex('#FF6B6B'),
                ),
                _buildSummaryCard(
                  'Balance',
                  currencyFormat.format(balance),
                  balance >= 0
                      ? PdfColor.fromHex('#6C63FF')
                      : PdfColor.fromHex('#FF6B6B'),
                ),
              ],
            ),

            pw.SizedBox(height: 30),

            // Transactions Table
            pw.Text(
              'Transactions (${transactions.length})',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),

            pw.SizedBox(height: 15),

            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                // Header Row
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F5F5F5'),
                  ),
                  children: [
                    _buildTableCell('Date', isHeader: true),
                    _buildTableCell('Category', isHeader: true),
                    _buildTableCell('Type', isHeader: true),
                    _buildTableCell('Amount', isHeader: true),
                  ],
                ),
                // Data Rows
                ...transactions.map((transaction) {
                  // Handle date - can be String or DateTime
                  final DateTime date;
                  if (transaction['date'] is String) {
                    date = DateTime.parse(transaction['date'] as String);
                  } else if (transaction['date'] is DateTime) {
                    date = transaction['date'] as DateTime;
                  } else {
                    date = DateTime.now();
                  }

                  final amount = (transaction['amount'] as num).toDouble();
                  final type = transaction['type'] as String;
                  final category = transaction['category'] as String;

                  return pw.TableRow(
                    children: [
                      _buildTableCell(DateFormat('MMM dd, yyyy').format(date)),
                      _buildTableCell(category),
                      _buildTableCell(
                        type.toUpperCase(),
                        color: type.toLowerCase() == 'expense'
                            ? PdfColor.fromHex('#FF6B6B')
                            : PdfColor.fromHex('#4CAF50'),
                      ),
                      _buildTableCell(
                        currencyFormat.format(amount),
                        color: type.toLowerCase() == 'expense'
                            ? PdfColor.fromHex('#FF6B6B')
                            : PdfColor.fromHex('#4CAF50'),
                      ),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 30),

            // Footer
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'Generated on ${DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          ];
        },
      ),
    );

    final fileName =
        '${title.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    return _savePdf(pdf, fileName);
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

  /// Helper: Build summary card
  static pw.Widget _buildSummaryCard(
    String label,
    String value,
    PdfColor color,
  ) {
    return pw.Container(
      width: 160,
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: color.shade(0.1),
        border: pw.Border.all(color: color, width: 2),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Build table cell
  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 12 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? (isHeader ? PdfColors.black : PdfColors.grey800),
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
