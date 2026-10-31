// lib/services/parse_analytics_service.dart
//
// Privacy-safe analytics for SMS parser monitoring.
//
// Design principles (see DECISIONS.md #24):
//  ● NEVER log message text, amounts, merchant names, or account numbers.
//  ● Only log categorical/technical metadata: country, package, parser name, reason.
//  ● All calls are wrapped in try/catch — analytics must never crash the parser.
//  ● Events use snake_case names ≤ 40 chars (Firebase Analytics limit).
//
// Events:
//  parse_success   — A transaction was successfully extracted.
//  parse_ignored   — The notification was intentionally skipped (OTP, promo, etc.).
//  parse_failed    — Parsing was attempted but no transaction could be extracted.

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Reason codes for [ParseAnalyticsService.logParseIgnored] and
/// [ParseAnalyticsService.logParseFailed].
///
/// Keep in sync with the Kotlin constants in NotificationListener.kt.
class ParseIgnoreReason {
  ParseIgnoreReason._();

  /// Message matched OTP pattern.
  static const String otp = 'otp';

  /// Message matched promotional/marketing pattern.
  static const String promo = 'promo';

  /// No monetary amount found.
  static const String noAmount = 'no_amount';

  /// No debit/credit verb found.
  static const String noVerb = 'no_verb';

  /// Sender ID did not match any known bank pattern.
  static const String noBankId = 'no_bank_id';

  /// Auto-detection is disabled by the user.
  static const String autoDetectOff = 'auto_detect_off';

  /// Duplicate — already seen this transaction hash today.
  static const String duplicate = 'duplicate';
}

class ParseFailedReason {
  ParseFailedReason._();

  /// Amount parsed but was zero or negative.
  static const String invalidAmount = 'invalid_amount';

  /// Unknown / unexpected error during parsing.
  static const String unknown = 'unknown';

  /// Rule file not loaded or country not in bank_rules.json.
  static const String noRule = 'no_rule';
}

/// Analytics service for tracking SMS parser events.
///
/// All methods are static, async, and safe to call from any isolate context.
/// Call these after parsing decisions — do NOT pass any financial data.
class ParseAnalyticsService {
  ParseAnalyticsService._();

  static FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Log a successfully parsed bank transaction.
  ///
  /// - [countryCode]: ISO 3166-1 alpha-2 (e.g. "IN", "AE", "NG").
  /// - [sourcePackage]: Android package name of the notification source
  ///   (e.g. "com.google.android.apps.messaging"). This is non-PII technical
  ///   metadata — it identifies which app the SMS came from, not the user.
  /// - [parserUsed]: Which parser handled the message ("india", "generic", "unknown").
  static Future<void> logParseSuccess({
    required String countryCode,
    required String sourcePackage,
    required String parserUsed,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'parse_success',
        parameters: {
          'country_code': _sanitize(countryCode, 5),
          'source_pkg': _truncatePackage(sourcePackage),
          'parser_used': _sanitize(parserUsed, 20),
        },
      );
    } catch (e) {
      debugPrint('⚠️ ANALYTICS: logParseSuccess error: $e');
    }
  }

  /// Log a notification that was intentionally skipped.
  ///
  /// - [reasonCode]: One of [ParseIgnoreReason] constants.
  static Future<void> logParseIgnored({
    required String countryCode,
    required String sourcePackage,
    required String reasonCode,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'parse_ignored',
        parameters: {
          'country_code': _sanitize(countryCode, 5),
          'source_pkg': _truncatePackage(sourcePackage),
          'reason_code': _sanitize(reasonCode, 20),
        },
      );
    } catch (e) {
      debugPrint('⚠️ ANALYTICS: logParseIgnored error: $e');
    }
  }

  /// Log an unexpected parsing failure (parsing was attempted but failed).
  ///
  /// - [parserUsed]: Which parser was attempted.
  /// - [reasonCode]: One of [ParseFailedReason] constants.
  static Future<void> logParseFailed({
    required String countryCode,
    required String sourcePackage,
    required String parserUsed,
    required String reasonCode,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'parse_failed',
        parameters: {
          'country_code': _sanitize(countryCode, 5),
          'source_pkg': _truncatePackage(sourcePackage),
          'parser_used': _sanitize(parserUsed, 20),
          'reason_code': _sanitize(reasonCode, 20),
        },
      );
    } catch (e) {
      debugPrint('⚠️ ANALYTICS: logParseFailed error: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Truncate and sanitize a string for use as an analytics parameter value.
  /// Firebase Analytics parameter values must be ≤ 100 chars.
  static String _sanitize(String value, int maxLength) {
    if (value.isEmpty) return 'unknown';
    final trimmed = value.trim();
    return trimmed.length > maxLength ? trimmed.substring(0, maxLength) : trimmed;
  }

  /// Extract only the last segment of a package name (e.g. "messaging" from
  /// "com.google.android.apps.messaging") to keep parameter values short and
  /// avoid logging full reverse-domain identifiers unnecessarily.
  ///
  /// Firebase Analytics param values are limited to 100 chars — full package
  /// names are fine, but we truncate to the last 40 chars for readability in
  /// BigQuery exports.
  static String _truncatePackage(String pkg) {
    if (pkg.isEmpty) return 'unknown';
    // Keep the full package but cap at 40 chars (take from end to preserve
    // the most meaningful part, e.g. "messaging" rather than "com.google.a...").
    if (pkg.length <= 40) return pkg;
    return pkg.substring(pkg.length - 40);
  }
}

