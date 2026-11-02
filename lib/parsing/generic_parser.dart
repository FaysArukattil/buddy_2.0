import 'bank_parser.dart';

/// A data-driven parser that applies the rules from one entry in
/// [bank_rules.json].
///
/// One instance is created per country rule. The rules specify:
///   - which notification packages and sender patterns to accept
///   - currency marker regex strings
///   - debit/credit keyword lists
///   - decimal/thousands separator characters for amount parsing
///   - number of decimal digits (0 for JPY/KRW/IDR/etc.)
///
/// Amount parsing handles three regional formats:
///   - Standard (US/UK/IN): 1,234.56  — comma=thousands, period=decimal
///   - European (DE/FR/ES/TR/BR): 1.234,56 — period=thousands, comma=decimal
///   - Indonesian IDR: 1.000.000 — period=thousands, no decimal for IDR
class GenericParser implements BankParser {
  @override
  final String countryCode;

  @override
  String get parserName => 'generic_$countryCode';

  final String _currencyCode;
  final String _currencySymbol;
  // ignore: unused_field  — kept for future diagnostics / Remote Config schema
  final List<String> _currencyMarkers;
  final RegExp _amountRegex;
  final String _decimalSeparator;
  // ignore: unused_field — kept for Remote Config schema parity with Kotlin
  final String _thousandsSeparator;
  // ignore: unused_field — kept for future zero-decimal enforcement
  final int _decimalDigits;
  final List<String> _debitKeywords;
  final List<String> _creditKeywords;
  final List<String> _bankIdentifiers;
  final List<String> _ignorePatterns;
  final Set<String> _notificationPackages;
  final List<String> _senderPatterns;

  // Common balance pattern keywords to exclude from amount extraction
  static final _balanceMarkers = [
    'bal', 'balance', 'avl bal', 'avbl bal', 'avail bal', 'available bal',
    'available balance', 'avail balance', 'a/c bal', 'saldo',
    'kontostand', 'disponível', 'solde',
    'limit', 'lmt', 'avl limit', 'avail limit', 'available limit', 'credit limit',
  ];

  // Universal credit limit clause masking pattern
  static final _creditLimitClause = RegExp(
    r'\b(?:Avl|Avail|Available)\.?\s+(?:Credit\s+)?(?:Limit|Lmt)\b\s*(?:is)?\s*:?\s*(?:INR|Rs\.?|₹|[A-Z]{3}|[$€£¥₩])?\s*[0-9,]*\.?\d+',
    caseSensitive: false,
  );

  // Universal ignore patterns applied before country-specific ones (mirrors GlobalBankParser.kt)
  static final _universalIgnore = [
    'otp', 'one time password', 'one-time password', 'verification code', 'login code',
    'failed', 'declined', 'unsuccessful', 'cancelled', 'rejected',
    'bill due', 'payment due', 'amount due', 'due on', 'min amount due', 'minimum amount due',
    'is overdue', 'in arrears',
    'requested money', 'has requested', 'request received', 'collect request',
    'pre-approved', 'pre approved', 'loan offer', 'loan approved',
    'congratulations', 'congrats', 'click here', 'tap here',
    'promo code', 'coupon code', 'discount code', 'cashback offer',
    'is blocked in your', 'asba', 'earmarked in your',
    'will be auto-debited', 'will be auto debited', 'mandate set for',
    'convert your', 'smartemi', 'into emi',
    // Arabic failure & decline phrases
    'عملية مرفوضة', 'تم رفض العملية', 'فشل العملية', 'عملية فاشلة',
    'تعذر إتمام العملية', 'لم تتم العملية', 'عملية غير ناجحة',
    'رصيد غير كافي', 'الرقم السري',
  ];

  GenericParser._({
    required this.countryCode,
    required String currencyCode,
    required String currencySymbol,
    required List<String> currencyMarkers,
    required RegExp amountRegex,
    required String decimalSeparator,
    required String thousandsSeparator,
    required int decimalDigits,
    required List<String> debitKeywords,
    required List<String> creditKeywords,
    required List<String> bankIdentifiers,
    required List<String> ignorePatterns,
    required Set<String> notificationPackages,
    required List<String> senderPatterns,
  })  : _currencyCode = currencyCode,
        _currencySymbol = currencySymbol,
        _currencyMarkers = currencyMarkers,
        _amountRegex = amountRegex,
        _decimalSeparator = decimalSeparator,
        _thousandsSeparator = thousandsSeparator,
        _decimalDigits = decimalDigits,
        _debitKeywords = debitKeywords,
        _creditKeywords = creditKeywords,
        _bankIdentifiers = bankIdentifiers,
        _ignorePatterns = ignorePatterns,
        _notificationPackages = notificationPackages,
        _senderPatterns = senderPatterns;

  /// Build a [GenericParser] from one JSON rule entry.
  factory GenericParser.fromRule(Map<String, dynamic> rule) {
    final country = (rule['country'] as String).toUpperCase();
    final currencyCode = rule['currencyCode'] as String;
    final currencySymbol = rule['currencySymbol'] as String;

    final currencyMarkers = _asList(rule['currencyMarkers']);
    final debitKeywords = _asList(rule['debitKeywords']);
    final creditKeywords = _asList(rule['creditKeywords']);
    final bankIdentifiers = _asList(rule['bankIdentifiers']);
    final ignorePatterns = _asList(rule['ignorePatterns']);
    final packages = _asList(rule['notificationPackages']).toSet();
    final senderPatterns = _asList(rule['senderPatterns']);

    final decimalSep = (rule['decimalSeparator'] as String?) ?? '.';
    final thousandsSep = (rule['thousandsSeparator'] as String?) ?? ',';
    final decimalDigits = (rule['decimalDigits'] as int?) ?? 2;

    // Build amount regex from the rule's pattern or derive one from markers
    final rawPattern = rule['amountPattern'] as String?;
    RegExp amountRegex;
    if (rawPattern != null) {
      try {
        amountRegex = RegExp(rawPattern, caseSensitive: false);
      } catch (_) {
        amountRegex = _buildAmountRegex(currencyMarkers, decimalSep);
      }
    } else {
      amountRegex = _buildAmountRegex(currencyMarkers, decimalSep);
    }

    return GenericParser._(
      countryCode: country,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      currencyMarkers: currencyMarkers,
      amountRegex: amountRegex,
      decimalSeparator: decimalSep,
      thousandsSeparator: thousandsSep,
      decimalDigits: decimalDigits,
      debitKeywords: debitKeywords,
      creditKeywords: creditKeywords,
      bankIdentifiers: bankIdentifiers,
      ignorePatterns: ignorePatterns,
      notificationPackages: packages,
      senderPatterns: senderPatterns,
    );
  }

  static List<String> _asList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.cast<String>();
    return [];
  }

  static RegExp _buildAmountRegex(
    List<String> markers,
    String decimalSep,
  ) {
    // Escape special regex chars in markers
    final escaped = markers.map(RegExp.escape).join('|');
    // Use decimalSep to optionally restrict which separator is matched
    final decimalEscaped = RegExp.escape(decimalSep);
    // Matches: <marker> <amount>  OR  <amount> <marker>
    return RegExp(
      '(?:$escaped)[\\s:.-]*([0-9]+(?:[$decimalEscaped,][0-9]+)*)'
      '|'
      '([0-9]+(?:[$decimalEscaped,][0-9]+)*)[\\s:.-]*(?:$escaped)',
      caseSensitive: false,
    );
  }

  // ── Main parse entry-point ──────────────────────────────────────────────

  @override
  ParsedTransaction? parse(String text, String sourcePackage) {
    final lower = text.toLowerCase();

    // 0. Universal ignore patterns applied before country-specific ones
    for (final pattern in _universalIgnore) {
      if (lower.contains(pattern)) {
        if (pattern == 'otp' &&
            !RegExp(r'\botp\b', caseSensitive: false).hasMatch(text)) {
          continue;
        }
        return null;
      }
    }

    // 1. Hard ignore patterns — no exceptions
    for (final pattern in _ignorePatterns) {
      if (lower.contains(pattern.toLowerCase())) {
        // Exception: "block your card" in a fraud disclaimer is OK
        if (pattern == 'otp' &&
            !RegExp(r'\botp\b', caseSensitive: false).hasMatch(text)) {
          continue;
        }
        return null;
      }
    }

    // 2. Source filter — must come from a known package or contain a sender
    if (!_isFromKnownSource(sourcePackage, text)) return null;

    // 3. Determine debit / credit
    final hasDebit = _hasDebitVerb(lower);
    final hasCredit = _hasCreditVerb(lower);
    if (!hasDebit && !hasCredit) return null;

    // 4. Must have at least one banking identifier
    if (!_hasBankIdentifier(lower)) return null;

    // 5. Extract amount (excluding balance)
    final amount = _extractAmount(text, lower);
    if (amount == null || amount <= 0) return null;

    // 6. Resolve type — credit takes precedence for refunds/reversals
    final isDebit = _resolveIsDebit(lower, hasDebit, hasCredit);
    final type = isDebit ? 'expense' : 'income';

    // 7. Category & icon (generic fallback)
    final (category, icon) = _detectCategory(lower, type);

    // 8. Build note
    final note = _buildNote(text, isDebit);

    return ParsedTransaction(
      amount: amount,
      type: type,
      category: category,
      icon: icon,
      note: note,
      currencyCode: _currencyCode,
      currencySymbol: _currencySymbol,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  bool _isFromKnownSource(String pkg, String text) {
    if (_notificationPackages.isEmpty) return true;
    if (_notificationPackages.contains(pkg)) return true;
    // Fallback: check if package name contains bank-related terms
    final lowerPkg = pkg.toLowerCase();
    if (['sms', 'message', 'messaging', 'mms', 'bank', 'pay', 'wallet']
        .any((t) => lowerPkg.contains(t))) { return true; }
    // Fallback: check sender patterns in the text
    final lowerText = text.toLowerCase();
    for (final pattern in _senderPatterns) {
      if (lowerText.contains(pattern.toLowerCase())) return true;
    }
    return false;
  }

  bool _hasDebitVerb(String lower) =>
      _debitKeywords.any((k) => lower.contains(k.toLowerCase()));

  bool _hasCreditVerb(String lower) =>
      _creditKeywords.any((k) => lower.contains(k.toLowerCase()));

  bool _hasBankIdentifier(String lower) {
    if (_bankIdentifiers.any((id) => lower.contains(id.toLowerCase()))) {
      return true;
    }
    // Universal fallbacks
    return lower.contains('account') ||
        lower.contains('a/c') ||
        lower.contains('card') ||
        lower.contains('bank') ||
        lower.contains('ref') ||
        lower.contains('balance');
  }

  bool _resolveIsDebit(String lower, bool hasDebit, bool hasCredit) {
    if (hasCredit && !hasDebit) return false;
    if (hasDebit && !hasCredit) return true;
    // Both: credit wins if refund/reversal/received/credited/deposited
    if (lower.contains('refund') ||
        lower.contains('reversal') ||
        lower.contains('received') ||
        lower.contains('credited') ||
        lower.contains('deposited') ||
        lower.contains('deposit')) { return false; }
    return true;
  }

  double? _extractAmount(String text, String lower) {
    // Mask credit limit clause so available limit is never extracted as spend
    final textWithoutLimit = text.replaceAll(_creditLimitClause, ' ');
    final allMatches = _amountRegex.allMatches(textWithoutLimit).toList();
    if (allMatches.isEmpty) return null;

    // Identify balance spans to exclude
    final balanceSpans = _findBalanceSpans(textWithoutLimit, lower);

    // Find the first valid non-balance amount match
    for (final match in allMatches) {
      final inBalance = balanceSpans.any((span) {
        return !(match.end <= span.$1 || match.start >= span.$2);
      });
      if (inBalance) continue;

      final raw = (match.group(1) ?? match.group(2) ?? match.group(3) ?? '');
      if (raw.isEmpty) continue;

      final parsed = _parseAmount(raw);
      if (parsed != null && parsed > 0) return parsed;
    }

    return null;
  }

  List<(int, int)> _findBalanceSpans(String text, String lower) {
    final spans = <(int, int)>[];
    for (final marker in _balanceMarkers) {
      int start = 0;
      while (true) {
        final idx = lower.indexOf(marker, start);
        if (idx < 0) break;
        // Consider up to 30 chars after the marker as part of the balance
        spans.add((idx, idx + marker.length + 30));
        start = idx + 1;
      }
    }
    return spans;
  }

  double? _parseAmount(String raw) {
    // Remove any whitespace
    var cleaned = raw.replaceAll(' ', '').replaceAll('\u00a0', '');

    if (_decimalDigits == 0) {
      // Currencies without sub-units (JPY, KRW, IDR, CLP): dots and commas are thousands
      cleaned = cleaned.replaceAll('.', '').replaceAll(',', '');
      return double.tryParse(cleaned);
    }

    if (_decimalSeparator == ',') {
      // European / South American / Turkish format: comma is decimal
      if (cleaned.contains(',')) {
        // e.g. "1.234,56" or "1 234,56" or "35,50"
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // No comma present — check if dot was used as decimal separator (e.g. "35.50 EUR")
        final dotParts = cleaned.split('.');
        if (dotParts.length == 2 && dotParts[1].length != 3) {
          // Single dot with non-3 decimal digits -> decimal point
          // Leave cleaned as is (e.g. "35.50")
        } else {
          // Dots are thousands separators (e.g. "1.000" or "1.234.567")
          cleaned = cleaned.replaceAll('.', '');
        }
      }
    } else {
      // Standard format: period is decimal, commas are thousands
      // Check if a European-style comma decimal was received in fallback rule (e.g. "349,00" or "54,99")
      if (cleaned.contains(',') && !cleaned.contains('.')) {
        final commaParts = cleaned.split(',');
        if (commaParts.length == 2 && commaParts[1].length != 3) {
          // Exactly 1 comma with 1 or 2 fractional digits -> decimal comma
          cleaned = cleaned.replaceAll(',', '.');
        } else {
          cleaned = cleaned.replaceAll(',', '');
        }
      } else {
        cleaned = cleaned.replaceAll(',', '');
      }
    }

    return double.tryParse(cleaned);
  }

  (String, int) _detectCategory(String lower, String type) {
    if (type == 'expense') {
      if (lower.contains('atm') ||
          lower.contains('cash') ||
          lower.contains('withdrawn') ||
          lower.contains('withdrawal')) {
        return ('Cash & ATM', 0xe8f4);
      }
      if (lower.contains('swiggy') ||
          lower.contains('zomato') ||
          lower.contains('talabat') ||
          lower.contains('deliveroo') ||
          lower.contains('careem food') ||
          lower.contains('al baik') ||
          lower.contains('jollibee') ||
          lower.contains('chipotle') ||
          lower.contains('nando') ||
          lower.contains('starbucks') ||
          lower.contains('coffee') ||
          lower.contains('cafe') ||
          lower.contains('canteen') ||
          lower.contains('dhaba') ||
          lower.contains('biryani') ||
          lower.contains('shawarma') ||
          lower.contains('bakery') ||
          lower.contains('baker') ||
          lower.contains('subway') ||
          lower.contains('mcdonald') ||
          lower.contains('kfc') ||
          lower.contains('burger') ||
          lower.contains('pizza') ||
          lower.contains('food') ||
          lower.contains('restaurant') ||
          lower.contains('dining')) {
        return ('Local Food', 63609);
      }
      if (lower.contains('carrefour') ||
          lower.contains('lulu') ||
          lower.contains('spinneys') ||
          lower.contains('waitrose') ||
          lower.contains('spar') ||
          lower.contains('supermarket') ||
          lower.contains('hypermarket') ||
          lower.contains('groceries') ||
          lower.contains('grocery') ||
          lower.contains('zepto') ||
          lower.contains('blinkit') ||
          lower.contains('instamart') ||
          lower.contains('bigbasket') ||
          lower.contains('dmart') ||
          lower.contains('jiomart')) {
        return ('Instamart', 983521);
      }
      if (lower.contains('amazon') ||
          lower.contains('flipkart') ||
          lower.contains('ikea') ||
          lower.contains('shein') ||
          lower.contains('temu') ||
          lower.contains('costco') ||
          lower.contains('target') ||
          lower.contains('walmart') ||
          lower.contains('zara') ||
          lower.contains('centrepoint') ||
          lower.contains('sharaf dg') ||
          lower.contains('shopping') ||
          lower.contains('mall')) {
        return ('Amazon', 63522);
      }
      if (lower.contains('uber') ||
          lower.contains('ola') ||
          lower.contains('rapido') ||
          lower.contains('careem') ||
          lower.contains('grab') ||
          lower.contains('bolt') ||
          lower.contains('yango') ||
          lower.contains('salik') ||
          lower.contains('toll') ||
          lower.contains('parking') ||
          lower.contains('taxi') ||
          lower.contains('metro') ||
          lower.contains('transport')) {
        return ('Transport', 63155);
      }
      if (lower.contains('dewa') ||
          lower.contains('sewa') ||
          lower.contains('stc') ||
          lower.contains('etisalat') ||
          lower.contains('recharge') ||
          lower.contains('wifi') ||
          lower.contains('broadband') ||
          lower.contains('electricity') ||
          lower.contains('water') ||
          lower.contains('gas') ||
          lower.contains('bill') ||
          lower.contains('utility')) {
        return ('Bills & Utilities', 983265);
      }
      if (lower.contains('netflix') ||
          lower.contains('spotify') ||
          lower.contains('hotstar') ||
          lower.contains('movie') ||
          lower.contains('cinema')) {
        return ('Entertainment', 0xe02c);
      }
      if (lower.contains('hospital') ||
          lower.contains('medical') ||
          lower.contains('pharmacy') ||
          lower.contains('clinic')) {
        return ('Medical', 63664);
      }
      if (lower.contains('fuel') ||
          lower.contains('petrol') ||
          lower.contains('diesel') ||
          lower.contains('gas station')) {
        return ('Fuel', 63597);
      }
      return ('Other', 983074);
    } else {
      if (lower.contains('salary') ||
          lower.contains('wage') ||
          lower.contains('payroll') ||
          lower.contains('salário') ||
          lower.contains('nómina')) {
        return ('Salary', 983128);
      }
      if (lower.contains('refund') ||
          lower.contains('reversed') ||
          lower.contains('reversal')) {
        return ('Refund', 983294);
      }
      if (lower.contains('cashback') || lower.contains('reward')) {
        return ('Cashback', 983797);
      }
      if (lower.contains('interest') || lower.contains('dividend')) {
        return ('Interest', 983336);
      }
      return ('Other', 983074);
    }
  }

  String _buildNote(String text, bool isDebit) {
    // 0. ATM / Cash withdrawal check
    final atmMatch = RegExp(
      r'(?:withdrawn\s*[@at]|cash\s+withdrawal\s+at)\s+([A-Za-z0-9\s_-]+?)(?:\s+on|\s+at|\s+bal|\s+ref|\s*\.|\s*$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (atmMatch != null) {
      final loc = _cleanMerchant(atmMatch.group(1) ?? '');
      if (loc.isNotEmpty) return 'Cash Withdrawal ($loc)';
    }

    // 1. UPI VPA with parenthesis check: VPA xyz@upi (Merchant Name)
    final vpaMatch = RegExp(
      r'VPA\s+[^@\s]+@[^\s]+\s*\(([^)]+)\)',
      caseSensitive: false,
    ).firstMatch(text);
    if (vpaMatch != null) {
      final vpaName = _cleanMerchant(vpaMatch.group(1) ?? '');
      if (_isValidMerchant(vpaName)) {
        return isDebit ? 'Paid to $vpaName' : 'Received from $vpaName';
      }
    }

    if (isDebit) {
      // Lookahead after at/to/towards/transfer to/paid to
      final toMatch = RegExp(
        r"\b(?:at|to|transfer\s+to|trf\s+to|paid\s+to|sent\s+to|towards)\s+([A-Za-z0-9&'][^,;:\n]*?)"
        r'(?=\s+(?:on|at|via|using|with|ref|for|dated|avl|avail|available|bal|balance|txn|from|to)\b|\.(?:\s|$)|[,;:\n]|$)',
        caseSensitive: false,
      ).firstMatch(text);
      if (toMatch != null) {
        final candidate = _cleanMerchant(toMatch.group(1) ?? '');
        if (_isValidMerchant(candidate)) {
          final isAt = RegExp(r'\bat\s+', caseSensitive: false).hasMatch(text);
          return isAt ? 'Paid at $candidate' : 'Paid to $candidate';
        }
      }
    } else {
      final fromMatch = RegExp(
        r"\bfrom\s+([A-Za-z0-9&'][^,;:\n]*?)"
        r'(?=\s+(?:on|at|via|using|with|ref|for|dated|avl|avail|available|bal|balance|txn|to)\b|\.(?:\s|$)|[,;:\n]|$)',
        caseSensitive: false,
      ).firstMatch(text);
      if (fromMatch != null) {
        final candidate = _cleanMerchant(fromMatch.group(1) ?? '');
        if (_isValidMerchant(candidate)) {
          return 'Received from $candidate';
        }
      }
    }

    return text.length > 100 ? text.substring(0, 100) : text;
  }

  String _cleanMerchant(String raw) {
    return raw
        .replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '')
        .replaceAll(RegExp(r'(\s+PVT\.?\s*LTD\.?|\s+PRIVATE\s+LIMITED)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'(\s+LTD\.?|\s+LIMITED)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+Ref\s+No.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+UPI.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+on\s+\d{2}.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+at\s+\d{2}:\d{2}.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*$'), '')
        .trim();
  }

  bool _isValidMerchant(String candidate) {
    if (candidate.length < 2) return false;
    final lower = candidate.toLowerCase();
    const notMerchantPrefixes = [
      'your', 'you', 'a/c', 'ac ', 'acct', 'account', 'card', 'the', 'my '
    ];
    if (notMerchantPrefixes.any((p) => lower.startsWith(p) || lower == p.trim())) {
      return false;
    }
    if (RegExp(r'^[0-9\-/.]+$').hasMatch(candidate)) return false;
    return candidate.contains(RegExp(r'[A-Za-z]'));
  }
}
