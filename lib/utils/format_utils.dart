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
}
