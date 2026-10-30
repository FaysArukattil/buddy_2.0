class FormatUtils {
  /// Format currency with rupee symbol and proper formatting
  /// Always shows exact amount with Indian numbering system (no K/L/Cr)
  static String formatCurrency(double value, {bool compact = false}) {
    // Ignore compact parameter - always show full amount
    return formatCurrencyFull(value.abs());
  }

  /// Format currency without compact notation (always show full amount)
  /// Always shows as integer (no decimals)
  static String formatCurrencyFull(double value) {
    final absValue = value.abs().round();
    // Always show as integer with Indian formatting
    return '₹${formatIndianNumber(absValue.toDouble())}';
  }

  /// Format large numbers with Indian numbering system
  static String formatIndianNumber(double value) {
    final rounded = value.roundToDouble().toInt();
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

  /// Format currency with Lakh ('L'), Crore ('Cr'), and 'k' notation for widgets
  /// and compact displays so large numbers (like 10 Lakh+) never clip or disappear.
  static String formatCompactCurrency(double value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 10000000) {
      // 1 Crore = 1,00,00,000
      final cr = abs / 10000000;
      final str = cr % 1 == 0 ? cr.toStringAsFixed(0) : cr.toStringAsFixed(1);
      return '$sign₹${str}Cr';
    } else if (abs >= 100000) {
      // 1 Lakh = 1,00,000 (e.g. 10 Lakh = 10L, 25.5 Lakh = 25.5L)
      final lk = abs / 100000;
      final str = lk % 1 == 0 ? lk.toStringAsFixed(0) : lk.toStringAsFixed(1);
      return '$sign₹${str}L';
    } else if (abs >= 10000) {
      // 10K+
      final k = abs / 1000;
      final str = k % 1 == 0 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '$sign₹${str}k';
    } else {
      return '$sign₹${formatIndianNumber(abs.roundToDouble())}';
    }
  }
}
