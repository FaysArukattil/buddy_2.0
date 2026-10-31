// lib/services/currency_service.dart
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Single source of truth for all currency formatting in the app.
///
/// Architecture:
/// - Stores three independent fields: countryCode, currencyCode, localeCode.
///   These are decoupled: e.g. a user in UAE can track in USD with en_US locale.
/// - currencySymbol is derived from the currencyCode.
/// - Loaded from SharedPreferences first (offline-first), then synced from Firestore.
/// - All UI, widgets, notifications, PDF/CSV, share texts must read from here.
/// - When currency changes: fires [currencyNotifier], refreshes widget + notifications.
class CurrencyService {
  CurrencyService._();

  // ── SharedPreferences keys ──
  static const String _keyCountryCode = 'user_country_code';
  static const String _keyCurrencyCode = 'user_currency_code';
  static const String _keyLocaleCode = 'user_locale_code';
  static const String _keyCurrencySymbol = 'user_currency_symbol';

  // ── Defaults (India / INR for existing users) ──
  static const String defaultCountryCode = 'IN';
  static const String defaultCurrencyCode = 'INR';
  static const String defaultLocaleCode = 'en_IN';
  static const String defaultCurrencySymbol = '₹';

  // ── Current values ──
  static String _countryCode = defaultCountryCode;
  static String _currencyCode = defaultCurrencyCode;
  static String _localeCode = defaultLocaleCode;
  static String _currencySymbol = defaultCurrencySymbol;

  // ── Reactive notifier for UI updates ──
  static final ValueNotifier<int> currencyNotifier = ValueNotifier<int>(0);

  static bool _initialized = false;

  // ── Getters ──
  static String get countryCode => _countryCode;
  static String get currencyCode => _currencyCode;
  static String get localeCode => _localeCode;
  static String get currencySymbol => _currencySymbol;
  static bool get isInitialized => _initialized;

  /// Whether the current currency uses the Indian numbering system (Lakh/Crore).
  static bool get usesIndianNumbering => _currencyCode == 'INR';

  /// Whether the current currency has zero decimal places (JPY, KRW, etc.)
  static bool get isZeroDecimalCurrency =>
      _zeroDecimalCurrencies.contains(_currencyCode);

  static const Set<String> _zeroDecimalCurrencies = {
    'JPY', 'KRW', 'VND', 'CLP', 'ISK', 'UGX', 'RWF', 'PYG', 'BIF', 'KMF',
    'GNF', 'MGA', 'XAF', 'XOF', 'XPF', 'DJF', 'CVE', 'HUF', // HUF effectively 0 decimals
  };

  // ── Initialization ──

  /// Load currency settings from SharedPreferences (instant, offline-first).
  /// Call this in app startup before any UI renders.
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _countryCode = prefs.getString(_keyCountryCode) ?? defaultCountryCode;
      _currencyCode = prefs.getString(_keyCurrencyCode) ?? defaultCurrencyCode;
      _localeCode = prefs.getString(_keyLocaleCode) ?? defaultLocaleCode;
      _currencySymbol =
          prefs.getString(_keyCurrencySymbol) ?? defaultCurrencySymbol;

      _initialized = true;
      debugPrint(
        '💱 CURRENCY: Initialized — $_countryCode / $_currencyCode / $_localeCode / $_currencySymbol',
      );
    } catch (e) {
      debugPrint('⚠️ CURRENCY: Init error (using defaults): $e');
      _initialized = true;
    }
  }

  /// Sync currency settings from Firestore (call after auth).
  static Future<void> syncFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      bool changed = false;

      if (data.containsKey('countryCode') &&
          data['countryCode'] is String &&
          (data['countryCode'] as String).isNotEmpty) {
        final remote = data['countryCode'] as String;
        if (_countryCode != remote) {
          _countryCode = remote;
          changed = true;
        }
      }

      if (data.containsKey('currencyCode') &&
          data['currencyCode'] is String &&
          (data['currencyCode'] as String).isNotEmpty) {
        final remote = data['currencyCode'] as String;
        if (_currencyCode != remote) {
          _currencyCode = remote;
          changed = true;
        }
      }

      if (data.containsKey('localeCode') &&
          data['localeCode'] is String &&
          (data['localeCode'] as String).isNotEmpty) {
        final remote = data['localeCode'] as String;
        if (_localeCode != remote) {
          _localeCode = remote;
          changed = true;
        }
      }

      if (data.containsKey('currencySymbol') &&
          data['currencySymbol'] is String &&
          (data['currencySymbol'] as String).isNotEmpty) {
        final remote = data['currencySymbol'] as String;
        if (_currencySymbol != remote) {
          _currencySymbol = remote;
          changed = true;
        }
      }

      if (changed) {
        await _saveToLocalCache();
        _notifyListeners();
        debugPrint(
          '☁️ CURRENCY: Synced from Firestore — $_countryCode / $_currencyCode / $_localeCode / $_currencySymbol',
        );
      }
    } catch (e) {
      debugPrint('⚠️ CURRENCY: Firestore sync error (non-critical): $e');
    }
  }

  // ── Update Methods ──

  /// Update the country (also updates currency/locale to the country's default).
  static Future<void> setCountry({
    required String countryCode,
    required String currencyCode,
    required String currencySymbol,
    required String localeCode,
  }) async {
    _countryCode = countryCode;
    _currencyCode = currencyCode;
    _currencySymbol = currencySymbol;
    _localeCode = localeCode;

    await _saveToLocalCache();
    await _syncToFirestore();
    _notifyListeners();

    debugPrint(
      '💱 CURRENCY: Updated — $countryCode / $currencyCode / $localeCode / $currencySymbol',
    );
  }

  /// Update just the currency (without changing country).
  /// For users who want to track in a different currency than their country's.
  static Future<void> setCurrency({
    required String currencyCode,
    required String currencySymbol,
  }) async {
    _currencyCode = currencyCode;
    _currencySymbol = currencySymbol;

    await _saveToLocalCache();
    await _syncToFirestore();
    _notifyListeners();

    debugPrint(
      '💱 CURRENCY: Currency changed to $currencyCode / $currencySymbol',
    );
  }

  /// Update just the locale (number formatting preference).
  static Future<void> setLocale(String localeCode) async {
    _localeCode = localeCode;

    await _saveToLocalCache();
    await _syncToFirestore();
    _notifyListeners();

    debugPrint('💱 CURRENCY: Locale changed to $localeCode');
  }

  // ── Formatting ──

  /// Format a currency amount using the user's currency and locale.
  /// This is the SINGLE entry point for all currency display in the app.
  ///
  /// [value] — the numeric amount (always positive, sign handled by caller)
  /// [compact] — ignored (kept for API compat; use [formatCompact] for compact)
  static String formatCurrency(double value, {bool compact = false}) {
    return formatFull(value.abs());
  }

  /// Format currency with full precision (no compact notation).
  /// Always shows as integer for INR, respects decimals for others.
  static String formatFull(double value) {
    final absValue = value.abs();

    if (usesIndianNumbering) {
      // Indian numbering system: 1,23,456
      final rounded = absValue.round();
      return '$_currencySymbol${_formatIndianNumber(rounded.toDouble())}';
    }

    if (isZeroDecimalCurrency) {
      final formatter = NumberFormat.currency(
        locale: _localeCode,
        symbol: _currencySymbol,
        decimalDigits: 0,
      );
      return formatter.format(absValue.round());
    }

    // International formatting
    // For whole numbers, show no decimals; for fractional, show up to 2
    if (absValue == absValue.roundToDouble() && absValue == absValue.round()) {
      final formatter = NumberFormat.currency(
        locale: _localeCode,
        symbol: _currencySymbol,
        decimalDigits: 0,
      );
      return formatter.format(absValue.round());
    }

    final formatter = NumberFormat.currency(
      locale: _localeCode,
      symbol: _currencySymbol,
      decimalDigits: 2,
    );
    return formatter.format(absValue);
  }

  /// Format currency in compact notation for widgets and tight spaces.
  /// Uses Lakh/Crore for India, K/M/B for international.
  static String formatCompact(double value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';

    if (usesIndianNumbering) {
      if (abs >= 10000000) {
        final cr = abs / 10000000;
        final str =
            cr % 1 == 0 ? cr.toStringAsFixed(0) : cr.toStringAsFixed(1);
        return '$sign$_currencySymbol${str}Cr';
      } else if (abs >= 100000) {
        final lk = abs / 100000;
        final str =
            lk % 1 == 0 ? lk.toStringAsFixed(0) : lk.toStringAsFixed(1);
        return '$sign$_currencySymbol${str}L';
      } else if (abs >= 10000) {
        final k = abs / 1000;
        final str =
            k % 1 == 0 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
        return '$sign$_currencySymbol${str}k';
      } else {
        return '$sign$_currencySymbol${_formatIndianNumber(abs.roundToDouble())}';
      }
    }

    // International compact: K, M, B
    if (abs >= 1000000000) {
      final b = abs / 1000000000;
      final str = b % 1 == 0 ? b.toStringAsFixed(0) : b.toStringAsFixed(1);
      return '$sign$_currencySymbol${str}B';
    } else if (abs >= 1000000) {
      final m = abs / 1000000;
      final str = m % 1 == 0 ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
      return '$sign$_currencySymbol${str}M';
    } else if (abs >= 10000) {
      final k = abs / 1000;
      final str = k % 1 == 0 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '$sign$_currencySymbol${str}K';
    } else {
      return '$sign${formatFull(abs)}';
    }
  }

  /// Format for PDF export. Uses the currency code (e.g. "Rs." for INR)
  /// to avoid font glyph issues with non-Unicode PDF fonts.
  /// When using a Unicode font in PDF, use [formatFull] instead.
  static String formatForPdf(double amount) {
    // With the Noto Sans Unicode font, we can use the real symbol
    return formatFull(amount.abs());
  }

  /// Format amount with explicit +/- sign prefix for income/expense display.
  static String formatSigned(double value, {required bool isIncome}) {
    final prefix = isIncome ? '+' : '-';
    return '$prefix${formatFull(value.abs())}';
  }

  /// Format amount with explicit +/- sign prefix in compact form.
  static String formatSignedCompact(double value, {required bool isIncome}) {
    final prefix = isIncome ? '+' : '-';
    return '$prefix${formatCompact(value.abs())}';
  }

  /// Get just the symbol (for use as a prefix in text fields etc.)
  static String get symbol => _currencySymbol;

  // ── Indian Number Formatting ──

  /// Format a number using the Indian numbering system (1,23,456).
  static String _formatIndianNumber(double value) {
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

  // ── Persistence ──

  static Future<void> _saveToLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_keyCountryCode, _countryCode),
        prefs.setString(_keyCurrencyCode, _currencyCode),
        prefs.setString(_keyLocaleCode, _localeCode),
        prefs.setString(_keyCurrencySymbol, _currencySymbol),
      ]);
    } catch (e) {
      debugPrint('⚠️ CURRENCY: Failed to save to local cache: $e');
    }
  }

  static Future<void> _syncToFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'countryCode': _countryCode,
        'currencyCode': _currencyCode,
        'localeCode': _localeCode,
        'currencySymbol': _currencySymbol,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ CURRENCY: Firestore sync error (non-critical): $e');
    }
  }

  static void _notifyListeners() {
    currencyNotifier.value++;
  }
}

