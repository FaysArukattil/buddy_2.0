import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:buddy/services/currency_service.dart';

class PdfService {
  static pw.MemoryImage? _cachedLogo;
  static pw.Font? _notoSansRegular;
  static pw.Font? _notoSansBold;

  /// Signature Luxury Theme Colors
  static final bgCanvas = PdfColor.fromHex('#091E1C'); // Deep spruce / dark emerald canvas
  static final cardSurface = PdfColor.fromHex('#102C28'); // Elevated dark emerald card
  static final cardSurfaceAlt = PdfColor.fromHex('#0C2420'); // Alternate row surface
  static final cardBorder = PdfColor.fromHex('#1C4740'); // Sleek teal border
  static final cardBorderSubtle = PdfColor.fromHex('#143833'); // Subtle divider line
  
  static final heroGradientStart = PdfColor.fromHex('#0D352F');
  static final heroGradientMid = PdfColor.fromHex('#144840');
  static final heroGradientEnd = PdfColor.fromHex('#1C5E54');
  
  static final textWhite = PdfColor.fromHex('#FFFFFF');
  static final textPrimary = PdfColor.fromHex('#F1F5F9');
  static final textSecondary = PdfColor.fromHex('#94A3B8');
  static final textMuted = PdfColor.fromHex('#64748B');
  static final textTealAccent = PdfColor.fromHex('#5EEAD4'); // Radiant mint teal
  
  static final incomeGreen = PdfColor.fromHex('#10B981'); // Vibrant mint
  static final incomeBg = PdfColor.fromHex('#064E3B'); // Deep green badge bg
  static final expenseRed = PdfColor.fromHex('#F87171'); // Coral red
  static final expenseBg = PdfColor.fromHex('#451212'); // Deep red badge bg
  static final surplusBlue = PdfColor.fromHex('#38BDF8'); // Cyan blue
  static final savingsPurple = PdfColor.fromHex('#A78BFA'); // Lavender purple
  static final goldAccent = PdfColor.fromHex('#FBBF24'); // Amber gold

  /// Loads the Noto Sans Unicode font for proper rendering of currency symbols
  /// (₹ ₦ ৳ ₫ ₺ ₱ € $ £ ₸ etc.) that Helvetica cannot display.
  static Future<pw.ThemeData> _getNotoSansTheme() async {
    if (_notoSansRegular == null || _notoSansBold == null) {
      try {
        final regularData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
        final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
        _notoSansRegular = pw.Font.ttf(regularData);
        _notoSansBold = pw.Font.ttf(boldData);
      } catch (e) {
        // Fallback to Helvetica if fonts fail to load
        _notoSansRegular = pw.Font.helvetica();
        _notoSansBold = pw.Font.helveticaBold();
      }
    }
    return pw.ThemeData.withFont(
      base: _notoSansRegular!,
      bold: _notoSansBold!,
    );
  }

  /// Loads the Buddy app logo from assets into memory for PDF embedding
  static Future<pw.MemoryImage?> _getAppLogo() async {
    if (_cachedLogo != null) return _cachedLogo;
    final candidatePaths = [
      'assets/images/app_logo.png',
      'assets/icon/playstore_icon_512.png',
      'assets/icon/app_icon.png',
    ];

    for (final path in candidatePaths) {
      try {
        final bytes = await rootBundle.load(path);
        _cachedLogo = pw.MemoryImage(bytes.buffer.asUint8List());
        return _cachedLogo;
      } catch (_) {
        // Try next candidate
      }
    }
    return null;
  }

  /// Sanitizes strings for PDF rendering with Noto Sans Unicode font.
  /// Strips emojis (unsupported by Noto Sans) and normalizes typographical chars.
  /// With Noto Sans loaded, currency symbols like ₹ ₦ ৳ ₫ ₺ ₱ € $ £ render correctly.
  static String _safeText(dynamic input) {
    if (input == null) return '';
    String text = input.toString();
    if (text.isEmpty) return '';

    // Normalize typographical characters
    text = text
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2022', '-');

    // Strip emoji ranges that even Noto Sans (Latin) cannot render
    text = text.replaceAll(
      RegExp(
        r'[\u{1F600}-\u{1F64F}|\u{1F300}-\u{1F5FF}|\u{1F680}-\u{1F6FF}|\u{1F700}-\u{1F77F}|\u{1F780}-\u{1F7FF}|\u{1F800}-\u{1F8FF}|\u{1F900}-\u{1F9FF}|\u{1FA00}-\u{1FA6F}|\u{1FA70}-\u{1FAFF}|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}]',
        unicode: true,
      ),
      '',
    );

    final result = text.trim();
    return result.isEmpty ? '-' : result;
  }

  /// Formats currency using CurrencyService (single source of truth).
  /// With Noto Sans loaded, the real currency symbol renders correctly.
  static String _formatCurrency(num amount) {
    return CurrencyService.formatForPdf(amount.toDouble());
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

  // ─────────────────────────────────────────────────────────────
  // 1. GENERATE SINGLE TRANSACTION PDF (DIGITAL LUXURY RECEIPT)
  // ─────────────────────────────────────────────────────────────
  static Future<File> generateSingleTransactionPdf(
    Map<String, dynamic> transaction,
  ) async {
    final pdf = pw.Document();
    final logoImage = await _getAppLogo();
    final notoTheme = await _getNotoSansTheme();

    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;
    final typeStr = (transaction['type'] as String?)?.toLowerCase().trim() ?? 'expense';
    final isIncome = typeStr == 'income';
    final date = _parseDate(transaction['date']);
    final category = _safeText(transaction['category'] ?? 'Other');

    // Clean title and notes
    String? noteRaw = transaction['note'] as String?;
    if (noteRaw == null || noteRaw.trim().isEmpty) {
      noteRaw = transaction['title'] as String?;
    }
    final note = (noteRaw != null && noteRaw.trim().isNotEmpty)
        ? _safeText(noteRaw)
        : null;

    final isAuto = transaction['auto_detected'] == true ||
        transaction['autoDetected'] == true;
    final source = transaction['notificationSource'] as String?;
    final sourceClean = source != null && source.isNotEmpty
        ? _safeText(source)
        : null;

    final rawId = transaction['id'] as String?;
    final shortId = (rawId != null && rawId.isNotEmpty)
        ? _safeText(rawId.substring(0, rawId.length > 10 ? 10 : rawId.length).toUpperCase())
        : null;

    final dateFormat = DateFormat('EEEE, dd MMMM yyyy');
    final timeFormat = DateFormat('hh:mm a');
    final generatedOn = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    final accentColor = isIncome ? incomeGreen : expenseRed;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: notoTheme,
        build: (context) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(
              color: bgCanvas,
              padding: const pw.EdgeInsets.fromLTRB(36, 36, 36, 32),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // ── Branded Header Bar ──
                  pw.Container(
                    padding: const pw.EdgeInsets.only(bottom: 18),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: cardBorder, width: 1.2),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Row(
                          children: [
                            if (logoImage != null)
                              pw.Container(
                                width: 46,
                                height: 46,
                                margin: const pw.EdgeInsets.only(right: 12),
                                decoration: pw.BoxDecoration(
                                  borderRadius: pw.BorderRadius.circular(12),
                                  border: pw.Border.all(
                                    color: textTealAccent,
                                    width: 1.2,
                                  ),
                                ),
                                child: pw.ClipRRect(
                                  horizontalRadius: 10,
                                  verticalRadius: 10,
                                  child: pw.Image(logoImage),
                                ),
                              )
                            else
                              pw.Container(
                                width: 46,
                                height: 46,
                                margin: const pw.EdgeInsets.only(right: 12),
                                decoration: pw.BoxDecoration(
                                  color: heroGradientMid,
                                  borderRadius: pw.BorderRadius.circular(12),
                                  border: pw.Border.all(
                                    color: textTealAccent,
                                    width: 1.2,
                                  ),
                                ),
                                child: pw.Center(
                                  child: pw.Text(
                                    'B',
                                    style: pw.TextStyle(
                                      color: textWhite,
                                      fontSize: 24,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'BUDDY',
                                  style: pw.TextStyle(
                                    fontSize: 20,
                                    fontWeight: pw.FontWeight.bold,
                                    color: textWhite,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  'Personal Finance & Expense Tracker',
                                  style: pw.TextStyle(
                                    fontSize: 9.5,
                                    color: textTealAccent,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: pw.BoxDecoration(
                                color: isIncome ? incomeBg : expenseBg,
                                borderRadius: pw.BorderRadius.circular(8),
                                border: pw.Border.all(
                                  color: accentColor,
                                  width: 1,
                                ),
                              ),
                              child: pw.Text(
                                isIncome ? 'INCOME RECEIPT' : 'EXPENSE RECEIPT',
                                style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: accentColor,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            if (shortId != null)
                              pw.Text(
                                'RECEIPT #$shortId',
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 22),

                  // ── Hero Amount Card (Color Themed Dark Emerald / Teal Glow) ──
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 22,
                    ),
                    decoration: pw.BoxDecoration(
                      gradient: pw.LinearGradient(
                        colors: [heroGradientStart, heroGradientMid, heroGradientEnd],
                        begin: pw.Alignment.topLeft,
                        end: pw.Alignment.bottomRight,
                      ),
                      borderRadius: pw.BorderRadius.circular(18),
                      border: pw.Border.all(
                        color: textTealAccent,
                        width: 1.2,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          isIncome ? 'TOTAL INCOME RECEIVED' : 'TOTAL AMOUNT PAID',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: textTealAccent,
                            letterSpacing: 1.4,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          _formatCurrency(amount),
                          style: pw.TextStyle(
                            fontSize: 34,
                            fontWeight: pw.FontWeight.bold,
                            color: textWhite,
                            letterSpacing: -0.5,
                          ),
                        ),
                        pw.SizedBox(height: 10),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromHex('#000000'),
                            borderRadius: pw.BorderRadius.circular(14),
                            border: pw.Border.all(
                              color: incomeGreen,
                              width: 0.8,
                            ),
                          ),
                          child: pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text(
                                '[OK] Verified & Recorded in Buddy',
                                style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: incomeGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 22),

                  // ── Itemized Specifications Table ──
                  pw.Text(
                    'TRANSACTION SPECIFICATIONS',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: textTealAccent,
                      letterSpacing: 0.8,
                    ),
                  ),
                  pw.SizedBox(height: 10),

                  pw.Container(
                    decoration: pw.BoxDecoration(
                      color: cardSurface,
                      borderRadius: pw.BorderRadius.circular(14),
                      border: pw.Border.all(
                        color: cardBorder,
                        width: 1.2,
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        _buildDarkReceiptRow('Category', category, isBold: true, valueColor: textWhite),
                        _buildDarkDivider(),
                        _buildDarkReceiptRow(
                          'Transaction Type',
                          isIncome ? 'Income' : 'Expense',
                          valueColor: accentColor,
                          isBold: true,
                        ),
                        _buildDarkDivider(),
                        _buildDarkReceiptRow('Date Logged', dateFormat.format(date)),
                        _buildDarkDivider(),
                        _buildDarkReceiptRow('Time Logged', timeFormat.format(date)),
                        _buildDarkDivider(),
                        _buildDarkReceiptRow(
                          'Entry Method',
                          isAuto
                              ? (sourceClean != null ? 'Auto ($sourceClean)' : 'Bank SMS Notification')
                              : 'Manual User Entry',
                          valueColor: isAuto ? goldAccent : textPrimary,
                        ),
                        if (rawId != null && rawId.isNotEmpty) ...[
                          _buildDarkDivider(),
                          _buildDarkReceiptRow('Internal Reference', _safeText(rawId), valueColor: textSecondary),
                        ],
                      ],
                    ),
                  ),

                  // ── Notes / Remarks Card ──
                  if (note != null && note.isNotEmpty && note != '-') ...[
                    pw.SizedBox(height: 16),
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(14),
                      decoration: pw.BoxDecoration(
                        color: cardSurface,
                        borderRadius: pw.BorderRadius.circular(12),
                        border: pw.Border.all(
                          color: cardBorder,
                          width: 1,
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'NOTES & REMARKS',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: textTealAccent,
                              letterSpacing: 0.8,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text(
                            note,
                            style: pw.TextStyle(
                              fontSize: 11,
                              color: textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  pw.Spacer(),

                  // ── Official Play Store QR & App Invite Card ──
                  _buildPlayStoreQrCard(logoImage: logoImage, isCompact: false),

                  // ── Footer ──
                  pw.Container(
                    padding: const pw.EdgeInsets.only(top: 12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(color: cardBorder, width: 1),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Buddy Expense Tracker | Verified Financial Record',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            color: textSecondary,
                          ),
                        ),
                        pw.Text(
                          'Exported on $generatedOn',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            color: textTealAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return _savePdf(
      pdf,
      'buddy_receipt_${rawId ?? DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. GENERATE MULTIPLE TRANSACTIONS STATEMENT & ANALYTICS REPORT
  // ─────────────────────────────────────────────────────────────
  static Future<File> generateMultipleTransactionsPdf({
    required List<Map<String, dynamic>> transactions,
    required String title,
    String? subtitle,
  }) async {
    final pdf = pw.Document();
    final logoImage = await _getAppLogo();
    final notoTheme = await _getNotoSansTheme();

    final dateFormat = DateFormat('dd MMM yyyy');
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
      final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
      final type = (t['type'] as String?)?.toLowerCase().trim() ?? 'expense';
      final category = _safeText(t['category'] ?? 'Other');

      if (type == 'income') {
        totalIncome += amount;
        incomeCount++;
        incomeByCategory[category] = (incomeByCategory[category] ?? 0) + amount;
        incomeCountByCategory[category] =
            (incomeCountByCategory[category] ?? 0) + 1;

        if (maxIncomeTxn == null ||
            amount > ((maxIncomeTxn['amount'] as num?)?.toDouble() ?? 0.0)) {
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
            amount > ((maxExpenseTxn['amount'] as num?)?.toDouble() ?? 0.0)) {
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
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 26),
          theme: notoTheme,
          buildBackground: (context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Container(color: bgCanvas),
            );
          },
        ),
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: cardBorder, width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Buddy Expense Tracker | Executive Statement | Confidential',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    color: textSecondary,
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: textTealAccent,
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            // ── Executive Branded Header ──
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  colors: [heroGradientStart, heroGradientMid, heroGradientEnd],
                  begin: pw.Alignment.topLeft,
                  end: pw.Alignment.bottomRight,
                ),
                borderRadius: pw.BorderRadius.circular(16),
                border: pw.Border.all(
                  color: textTealAccent,
                  width: 1.2,
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Row(
                    children: [
                      if (logoImage != null)
                        pw.Container(
                          width: 46,
                          height: 46,
                          margin: const pw.EdgeInsets.only(right: 12),
                          decoration: pw.BoxDecoration(
                            borderRadius: pw.BorderRadius.circular(12),
                            border: pw.Border.all(
                              color: textTealAccent,
                              width: 1.2,
                            ),
                          ),
                          child: pw.ClipRRect(
                            horizontalRadius: 10,
                            verticalRadius: 10,
                            child: pw.Image(logoImage),
                          ),
                        )
                      else
                        pw.Container(
                          width: 46,
                          height: 46,
                          margin: const pw.EdgeInsets.only(right: 12),
                          decoration: pw.BoxDecoration(
                            color: heroGradientMid,
                            borderRadius: pw.BorderRadius.circular(12),
                            border: pw.Border.all(
                              color: textTealAccent,
                              width: 1.2,
                            ),
                          ),
                          child: pw.Center(
                            child: pw.Text(
                              'B',
                              style: pw.TextStyle(
                                color: textWhite,
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            _safeText(title),
                            style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: textWhite,
                            ),
                          ),
                          if (subtitle != null && subtitle.isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(
                              _safeText(subtitle),
                              style: pw.TextStyle(
                                fontSize: 11,
                                color: textTealAccent,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Buddy Expense Tracker | Executive Financial Statement',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#000000'),
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(
                            color: goldAccent,
                            width: 0.8,
                          ),
                        ),
                        child: pw.Text(
                          'OFFICIAL REPORT',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: goldAccent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        dateFormat.format(DateTime.now()),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: textWhite,
                        ),
                      ),
                      pw.Text(
                        timeFormat.format(DateTime.now()),
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // ── Executive Summary KPI Cards (Row of 4) ──
            pw.Row(
              children: [
                pw.Expanded(
                  child: _buildDarkSummaryCard(
                    'TOTAL INCOME',
                    _formatCurrency(totalIncome),
                    incomeGreen,
                    '$incomeCount txn${incomeCount == 1 ? "" : "s"}',
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: _buildDarkSummaryCard(
                    'TOTAL EXPENSE',
                    _formatCurrency(totalExpense),
                    expenseRed,
                    '$expenseCount txn${expenseCount == 1 ? "" : "s"}',
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: _buildDarkSummaryCard(
                    'NET BALANCE',
                    '${netBalance >= 0 ? "+" : ""}${_formatCurrency(netBalance)}',
                    netBalance >= 0 ? surplusBlue : expenseRed,
                    netBalance >= 0 ? 'Surplus Reserve' : 'Deficit',
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: _buildDarkSummaryCard(
                    'SAVINGS RATE',
                    savingsRate != null
                        ? '${savingsRate.toStringAsFixed(1)}%'
                        : 'N/A',
                    savingsRate != null && savingsRate >= 0
                        ? savingsPurple
                        : goldAccent,
                    totalIncome > 0
                        ? 'Efficiency ratio'
                        : 'No income logged',
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 14),

            // ── Key Analytical Insights Highlight Box ──
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: pw.BoxDecoration(
                color: cardSurface,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(
                  color: cardBorder,
                  width: 1,
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: _buildDarkInsightItem(
                      'Avg Spend / Txn',
                      _formatCurrency(avgExpensePerTxn),
                    ),
                  ),
                  pw.Container(width: 1, height: 26, color: cardBorder),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: _buildDarkInsightItem(
                      'Total Logs',
                      '${transactions.length} records ($expenseCount exp, $incomeCount inc)',
                    ),
                  ),
                  pw.Container(width: 1, height: 26, color: cardBorder),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: _buildDarkInsightItem(
                      'Peak Expense',
                      maxExpenseTxn != null
                          ? '${_formatCurrency((maxExpenseTxn['amount'] as num?)?.toDouble() ?? 0.0)} (${_safeText(maxExpenseTxn['category'])})'
                          : 'None',
                    ),
                  ),
                  if (maxIncomeTxn != null) ...[
                    pw.Container(width: 1, height: 26, color: cardBorder),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: _buildDarkInsightItem(
                        'Peak Income',
                        '${_formatCurrency((maxIncomeTxn['amount'] as num?)?.toDouble() ?? 0.0)} (${_safeText(maxIncomeTxn['category'])})',
                      ),
                    ),
                  ],
                ],
              ),
            ),

            pw.SizedBox(height: 18),

            // ── Top Spending Categories Section ──
            pw.Text(
              'TOP SPENDING CATEGORIES BREAKDOWN',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: textTealAccent,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 8),

            if (sortedExpenses.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: cardSurface,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: cardBorder),
                ),
                child: pw.Text(
                  'No expenses recorded for this period.',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: textSecondary,
                  ),
                ),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(
                  color: cardBorder,
                  width: 0.8,
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(32),
                  1: pw.FlexColumnWidth(3),
                  2: pw.FixedColumnWidth(75),
                  3: pw.FixedColumnWidth(95),
                  4: pw.FixedColumnWidth(65),
                  5: pw.FlexColumnWidth(2.5),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: heroGradientStart,
                    ),
                    children: [
                      _buildDarkTableCell('#', isHeader: true),
                      _buildDarkTableCell('Category', isHeader: true),
                      _buildDarkTableCell('Count', isHeader: true),
                      _buildDarkTableCell('Amount', isHeader: true),
                      _buildDarkTableCell('Share %', isHeader: true),
                      _buildDarkTableCell('Visual Share', isHeader: true),
                    ],
                  ),
                  ...sortedExpenses.asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final catName = _safeText(entry.value.key);
                    final catAmt = entry.value.value;
                    final catCount = expenseCountByCategory[entry.value.key] ?? 1;
                    final pct = totalExpense > 0
                        ? (catAmt / totalExpense * 100)
                        : 0.0;
                    final isEven = rank % 2 == 0;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: isEven ? cardSurface : cardSurfaceAlt,
                      ),
                      children: [
                        _buildDarkTableCell('$rank', color: textTealAccent),
                        _buildDarkTableCell(catName, color: textWhite),
                        _buildDarkTableCell('$catCount txns', color: textSecondary),
                        _buildDarkTableCell(
                          _formatCurrency(catAmt),
                          color: expenseRed,
                          isBold: true,
                        ),
                        _buildDarkTableCell('${pct.toStringAsFixed(1)}%', color: textWhite),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: pw.Stack(
                            children: [
                              pw.Container(
                                height: 5,
                                decoration: pw.BoxDecoration(
                                  color: cardBorder,
                                  borderRadius: pw.BorderRadius.circular(2.5),
                                ),
                              ),
                              pw.Container(
                                width: (pct * 0.9).clamp(2.0, 90.0),
                                height: 5,
                                decoration: pw.BoxDecoration(
                                  color: expenseRed,
                                  borderRadius: pw.BorderRadius.circular(2.5),
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
              pw.SizedBox(height: 18),
              pw.Text(
                'INCOME SOURCES BREAKDOWN',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: textTealAccent,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                  color: cardBorder,
                  width: 0.8,
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(32),
                  1: pw.FlexColumnWidth(3),
                  2: pw.FixedColumnWidth(75),
                  3: pw.FixedColumnWidth(95),
                  4: pw.FixedColumnWidth(65),
                  5: pw.FlexColumnWidth(2.5),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: heroGradientStart,
                    ),
                    children: [
                      _buildDarkTableCell('#', isHeader: true),
                      _buildDarkTableCell('Source', isHeader: true),
                      _buildDarkTableCell('Count', isHeader: true),
                      _buildDarkTableCell('Amount', isHeader: true),
                      _buildDarkTableCell('Share %', isHeader: true),
                      _buildDarkTableCell('Visual Share', isHeader: true),
                    ],
                  ),
                  ...sortedIncomes.asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final catName = _safeText(entry.value.key);
                    final catAmt = entry.value.value;
                    final catCount = incomeCountByCategory[entry.value.key] ?? 1;
                    final pct = totalIncome > 0
                        ? (catAmt / totalIncome * 100)
                        : 0.0;
                    final isEven = rank % 2 == 0;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: isEven ? cardSurface : cardSurfaceAlt,
                      ),
                      children: [
                        _buildDarkTableCell('$rank', color: textTealAccent),
                        _buildDarkTableCell(catName, color: textWhite),
                        _buildDarkTableCell('$catCount txns', color: textSecondary),
                        _buildDarkTableCell(
                          _formatCurrency(catAmt),
                          color: incomeGreen,
                          isBold: true,
                        ),
                        _buildDarkTableCell('${pct.toStringAsFixed(1)}%', color: textWhite),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: pw.Stack(
                            children: [
                              pw.Container(
                                height: 5,
                                decoration: pw.BoxDecoration(
                                  color: cardBorder,
                                  borderRadius: pw.BorderRadius.circular(2.5),
                                ),
                              ),
                              pw.Container(
                                width: (pct * 0.9).clamp(2.0, 90.0),
                                height: 5,
                                decoration: pw.BoxDecoration(
                                  color: incomeGreen,
                                  borderRadius: pw.BorderRadius.circular(2.5),
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

            pw.SizedBox(height: 20),

            // ── Itemized Transactions Log Table ──
            pw.Text(
              'ITEMIZED TRANSACTIONS LOG (${transactions.length})',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: textTealAccent,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 8),

            pw.Table(
              border: pw.TableBorder.all(
                color: cardBorder,
                width: 0.8,
              ),
              columnWidths: const {
                0: pw.FixedColumnWidth(80),
                1: pw.FixedColumnWidth(90),
                2: pw.FlexColumnWidth(3),
                3: pw.FixedColumnWidth(60),
                4: pw.FixedColumnWidth(85),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: heroGradientStart,
                  ),
                  children: [
                    _buildDarkTableCell('Date', isHeader: true),
                    _buildDarkTableCell('Category', isHeader: true),
                    _buildDarkTableCell('Description / Note', isHeader: true),
                    _buildDarkTableCell('Type', isHeader: true),
                    _buildDarkTableCell('Amount', isHeader: true),
                  ],
                ),
                ...sortedTxns.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final t = entry.value;
                  final dt = _parseDate(t['date']);
                  final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
                  final type = (t['type'] as String?)?.toLowerCase().trim() ?? 'expense';
                  final isIncome = type == 'income';

                  String? noteText = t['note'] as String?;
                  if (noteText == null || noteText.trim().isEmpty) {
                    noteText = t['title'] as String?;
                  }
                  final noteClean = (noteText != null && noteText.trim().isNotEmpty)
                      ? _safeText(noteText)
                      : '-';

                  final category = _safeText(t['category'] ?? 'Other');
                  final isEven = idx % 2 == 0;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: isEven ? cardSurface : cardSurfaceAlt,
                    ),
                    children: [
                      _buildDarkTableCell(dateFormat.format(dt), color: textSecondary),
                      _buildDarkTableCell(category, color: textWhite, isBold: true),
                      _buildDarkTableCell(noteClean, color: textPrimary),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 5,
                        ),
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: pw.BoxDecoration(
                            color: isIncome ? incomeBg : expenseBg,
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(
                              color: isIncome ? incomeGreen : expenseRed,
                              width: 0.6,
                            ),
                          ),
                          child: pw.Center(
                            child: pw.Text(
                              isIncome ? 'INCOME' : 'EXPENSE',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                fontWeight: pw.FontWeight.bold,
                                color: isIncome ? incomeGreen : expenseRed,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _buildDarkTableCell(
                        '${isIncome ? "+" : "-"}${_formatCurrency(amt)}',
                        color: isIncome ? incomeGreen : expenseRed,
                        isBold: true,
                      ),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 16),

            // ── Official Play Store QR & App Invite Card ──
            _buildPlayStoreQrCard(logoImage: logoImage, isCompact: false),
          ];
        },
      ),
    );

    final cleanTitle = _safeText(title).replaceAll(' ', '_').toLowerCase();
    final fileName = 'buddy_${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    return _savePdf(pdf, fileName);
  }

  // ─────────────────────────────────────────────────────────────
  // REUSABLE DARK THEME PDF BUILDER HELPERS
  // ─────────────────────────────────────────────────────────────

  /// Play Store QR card with app branding, inviting design and direct link
  static pw.Widget _buildPlayStoreQrCard({
    required pw.MemoryImage? logoImage,
    bool isCompact = false,
  }) {
    const playStoreUrl =
        'https://play.google.com/store/apps/details?id=com.faysarukattil.buddy';

    return pw.Container(
      margin: pw.EdgeInsets.symmetric(vertical: isCompact ? 6 : 10),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: cardSurface,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: cardBorder, width: 1.1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Left Content: Branding, Tagline, & Description
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Row(
                  children: [
                    if (logoImage != null)
                      pw.Container(
                        width: 20,
                        height: 20,
                        margin: const pw.EdgeInsets.only(right: 8),
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(5),
                          image: pw.DecorationImage(
                            image: logoImage,
                            fit: pw.BoxFit.cover,
                          ),
                        ),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'BUDDY EXPENSE TRACKER',
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: textTealAccent,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.Text(
                          'Available on Google Play',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Scan the QR code with your phone camera to download Buddy for free or leave a review on Google Play.',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: textWhite,
                    lineSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2.5,
                  ),
                  decoration: pw.BoxDecoration(
                    color: incomeBg,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: cardBorder, width: 0.8),
                  ),
                  child: pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Container(
                        width: 4,
                        height: 4,
                        decoration: pw.BoxDecoration(
                          color: textTealAccent,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        'OFFICIAL APP | VERIFIED STORE LISTING',
                        style: pw.TextStyle(
                          fontSize: 6.5,
                          fontWeight: pw.FontWeight.bold,
                          color: textTealAccent,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(width: 14),

          // Right Side: Luxury QR Code Container
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: textTealAccent, width: 1.5),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: playStoreUrl,
                  width: isCompact ? 54 : 62,
                  height: isCompact ? 54 : 62,
                  color: bgCanvas,
                  backgroundColor: PdfColors.white,
                ),
                pw.SizedBox(height: 3),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1.5,
                  ),
                  decoration: pw.BoxDecoration(
                    color: bgCanvas,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Text(
                    'SCAN TO OPEN',
                    style: pw.TextStyle(
                      fontSize: 6,
                      fontWeight: pw.FontWeight.bold,
                      color: textTealAccent,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Build clean dark receipt row with label on left and value on right
  static pw.Widget _buildDarkReceiptRow(
    String label,
    String value, {
    PdfColor? valueColor,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10.5,
              color: textSecondary,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valueColor ?? textWhite,
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Subtle divider between dark receipt rows
  static pw.Widget _buildDarkDivider() {
    return pw.Divider(
      color: cardBorderSubtle,
      height: 1,
      thickness: 0.8,
    );
  }

  /// Helper: Build executive summary KPI card in dark luxury style
  static pw.Widget _buildDarkSummaryCard(
    String label,
    String value,
    PdfColor accentColor, [
    String? subtitle,
  ]) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: pw.BoxDecoration(
        color: cardSurface,
        border: pw.Border(
          top: pw.BorderSide(color: accentColor, width: 2.5),
          left: pw.BorderSide(color: cardBorder, width: 1),
          right: pw.BorderSide(color: cardBorder, width: 1),
          bottom: pw.BorderSide(color: cardBorder, width: 1),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              color: accentColor,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
              color: textWhite,
            ),
          ),
          if (subtitle != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              subtitle,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Helper: Build insight item in dark luxury style
  static pw.Widget _buildDarkInsightItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 7.5,
            color: textSecondary,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: textWhite,
          ),
        ),
      ],
    );
  }

  /// Helper: Build dark table cell
  static pw.Widget _buildDarkTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 8.5 : 8,
          fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? (isHeader ? textTealAccent : textPrimary),
        ),
      ),
    );
  }

  /// Save PDF to device storage
  static Future<File> _savePdf(pw.Document pdf, String fileName) async {
    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Open PDF file using default system viewer
  static Future<void> openPdf(File file) async {
    await OpenFile.open(file.path);
  }

  /// Share PDF file via system share sheet
  static Future<void> sharePdf(File file) async {
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: file.path.split('/').last,
    );
  }

  /// Print PDF to local or wireless printer
  static Future<void> printPdf(File file) async {
    await Printing.layoutPdf(
      onLayout: (format) async => await file.readAsBytes(),
    );
  }
}
