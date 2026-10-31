import 'package:buddy/services/currency_service.dart';

/// Formatting utilities that delegate to [CurrencyService] — the single source
/// of truth for all currency display in the app.
///
/// The static API surface is kept identical so that existing call-sites
/// (`FormatUtils.formatCurrency(...)`) continue to work without changes.
class FormatUtils {
  /// Format currency with the user's chosen symbol and proper locale formatting.
  /// Always shows exact amount (no compact notation).
  static String formatCurrency(double value, {bool compact = false}) {
    return CurrencyService.formatFull(value.abs());
  }

  /// Format currency without compact notation (always show full amount).
  static String formatCurrencyFull(double value) {
    return CurrencyService.formatFull(value.abs());
  }

  /// Format a number using the Indian numbering system (1,23,456).
  /// Kept as a public helper for any legacy callers.
  static String formatIndianNumber(double value) {
    if (CurrencyService.usesIndianNumbering) {
      // Delegate to CurrencyService internal formatting by stripping the symbol
      final full = CurrencyService.formatFull(value.abs());
      return full.replaceFirst(CurrencyService.currencySymbol, '').trim();
    }
    // Fallback for non-INR: just return the number with standard grouping
    final rounded = value.abs().roundToDouble().toInt();
    final str = rounded.toString();
    if (str.length <= 3) return str;

    final lastThree = str.substring(str.length - 3);
    final remaining = str.substring(0, str.length - 3);

    final buffer = StringBuffer();
    var count = 0;

    for (var i = remaining.length - 1; i >= 0; i--) {
      if (count == 2) {
        buffer.write(',');
        count = 0;
      }
      buffer.write(remaining[i]);
      count++;
    }

    return '${buffer.toString().split('').reversed.join()},$lastThree';
  }

  /// Format currency with compact notation (K/M/B or L/Cr) for widgets
  /// and tight spaces so large numbers never clip or disappear.
  static String formatCompactCurrency(double value) {
    return CurrencyService.formatCompact(value);
  }
}
