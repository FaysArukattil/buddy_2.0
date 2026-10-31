/// Abstract interface for bank SMS / notification parsers.
///
/// Implementations must be stateless — [parse] may be called concurrently.
///
/// Result model:
///   - `null`  → message is not a financial transaction (ignore silently)
///   - non-null → parsed transaction data
library;

/// Parsed result from a bank notification.
class ParsedTransaction {
  final double amount;
  final String type; // 'expense' | 'income'
  final String category;
  final int icon;
  final String note;
  final DateTime? date;
  final String? upiRef;
  final String? currencyCode;
  final String? currencySymbol;

  const ParsedTransaction({
    required this.amount,
    required this.type,
    required this.category,
    required this.icon,
    required this.note,
    this.date,
    this.upiRef,
    this.currencyCode,
    this.currencySymbol,
  });

  @override
  String toString() =>
      'ParsedTransaction(amount: $amount, type: $type, category: $category, '
      'currency: $currencyCode, note: "$note")';
}

/// Base interface all parsers implement.
abstract class BankParser {
  /// The ISO-3166-1 alpha-2 country code this parser handles.
  String get countryCode;

  /// Human-readable name for logging/analytics.
  String get parserName;

  /// Returns a [ParsedTransaction] if [text] describes a completed financial
  /// transaction from [sourcePackage], or `null` if the message should be
  /// ignored.
  ///
  /// [text] is the full concatenated notification title + body text.
  /// [sourcePackage] is the Android package name of the app that sent it.
  ParsedTransaction? parse(String text, String sourcePackage);
}

