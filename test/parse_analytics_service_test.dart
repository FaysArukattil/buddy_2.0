// test/parse_analytics_service_test.dart
//
// Smoke tests for ParseAnalyticsService.
//
// Strategy: Firebase Analytics cannot be initialized in unit tests without a
// real Firebase app — so we verify only that:
//   1. The method signatures exist and compile.
//   2. Calling the methods with valid inputs does NOT throw.
//   3. Calling them with empty/invalid inputs does NOT throw.
//
// The actual Firebase calls are wrapped in try/catch inside the service, so
// they will silently swallow any FirebaseApp-not-initialized errors in tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:buddy/services/parse_analytics_service.dart';

void main() {
  // No Firebase.initializeApp() — tests verify non-throwing behaviour only.

  group('ParseIgnoreReason constants', () {
    test('all reason constants are non-empty strings', () {
      expect(ParseIgnoreReason.otp, isNotEmpty);
      expect(ParseIgnoreReason.promo, isNotEmpty);
      expect(ParseIgnoreReason.noAmount, isNotEmpty);
      expect(ParseIgnoreReason.noVerb, isNotEmpty);
      expect(ParseIgnoreReason.noBankId, isNotEmpty);
      expect(ParseIgnoreReason.autoDetectOff, isNotEmpty);
      expect(ParseIgnoreReason.duplicate, isNotEmpty);
    });

    test('reason codes are under 20 chars (Firebase Analytics param limit guard)', () {
      for (final code in [
        ParseIgnoreReason.otp,
        ParseIgnoreReason.promo,
        ParseIgnoreReason.noAmount,
        ParseIgnoreReason.noVerb,
        ParseIgnoreReason.noBankId,
        ParseIgnoreReason.autoDetectOff,
        ParseIgnoreReason.duplicate,
      ]) {
        expect(code.length, lessThanOrEqualTo(20),
            reason: 'reason code "$code" exceeds 20 chars');
      }
    });
  });

  group('ParseFailedReason constants', () {
    test('all reason constants are non-empty strings', () {
      expect(ParseFailedReason.invalidAmount, isNotEmpty);
      expect(ParseFailedReason.unknown, isNotEmpty);
      expect(ParseFailedReason.noRule, isNotEmpty);
    });
  });

  group('ParseAnalyticsService._sanitize (via public API shape test)', () {
    // We can't call private _sanitize directly, but we can verify the public
    // methods accept edge-case inputs without throwing.

    test('logParseSuccess does not throw for valid inputs', () async {
      await expectLater(
        ParseAnalyticsService.logParseSuccess(
          countryCode: 'IN',
          sourcePackage: 'com.google.android.apps.messaging',
          parserUsed: 'india',
        ),
        completes,
      );
    });

    test('logParseSuccess does not throw for empty countryCode', () async {
      await expectLater(
        ParseAnalyticsService.logParseSuccess(
          countryCode: '',
          sourcePackage: 'com.android.messaging',
          parserUsed: 'generic',
        ),
        completes,
      );
    });

    test('logParseSuccess does not throw for very long package name', () async {
      final longPkg = 'a' * 200;
      await expectLater(
        ParseAnalyticsService.logParseSuccess(
          countryCode: 'AE',
          sourcePackage: longPkg,
          parserUsed: 'generic',
        ),
        completes,
      );
    });

    test('logParseIgnored does not throw for otp reason', () async {
      await expectLater(
        ParseAnalyticsService.logParseIgnored(
          countryCode: 'IN',
          sourcePackage: 'com.samsung.android.messaging',
          reasonCode: ParseIgnoreReason.otp,
        ),
        completes,
      );
    });

    test('logParseIgnored does not throw for promo reason', () async {
      await expectLater(
        ParseAnalyticsService.logParseIgnored(
          countryCode: 'NG',
          sourcePackage: 'com.android.mms',
          reasonCode: ParseIgnoreReason.promo,
        ),
        completes,
      );
    });

    test('logParseIgnored does not throw for no_amount reason', () async {
      await expectLater(
        ParseAnalyticsService.logParseIgnored(
          countryCode: 'KE',
          sourcePackage: 'com.android.messaging',
          reasonCode: ParseIgnoreReason.noAmount,
        ),
        completes,
      );
    });

    test('logParseIgnored does not throw for no_verb reason', () async {
      await expectLater(
        ParseAnalyticsService.logParseIgnored(
          countryCode: 'GB',
          sourcePackage: 'com.google.android.apps.messaging',
          reasonCode: ParseIgnoreReason.noVerb,
        ),
        completes,
      );
    });

    test('logParseIgnored does not throw for no_bank_id reason', () async {
      await expectLater(
        ParseAnalyticsService.logParseIgnored(
          countryCode: 'US',
          sourcePackage: 'com.android.messaging',
          reasonCode: ParseIgnoreReason.noBankId,
        ),
        completes,
      );
    });

    test('logParseFailed does not throw for invalid_amount reason', () async {
      await expectLater(
        ParseAnalyticsService.logParseFailed(
          countryCode: 'PK',
          sourcePackage: 'com.android.mms',
          parserUsed: 'generic',
          reasonCode: ParseFailedReason.invalidAmount,
        ),
        completes,
      );
    });

    test('logParseFailed does not throw for unknown reason', () async {
      await expectLater(
        ParseAnalyticsService.logParseFailed(
          countryCode: 'DE',
          sourcePackage: 'com.google.android.apps.messaging',
          parserUsed: 'generic',
          reasonCode: ParseFailedReason.unknown,
        ),
        completes,
      );
    });

    test('logParseFailed does not throw for no_rule reason', () async {
      await expectLater(
        ParseAnalyticsService.logParseFailed(
          countryCode: 'XX',
          sourcePackage: 'com.unknown.sms',
          parserUsed: 'generic',
          reasonCode: ParseFailedReason.noRule,
        ),
        completes,
      );
    });

    test('logParseSuccess does not throw for all known countries', () async {
      const countries = ['IN', 'AE', 'NG', 'KE', 'GB', 'DE', 'BR', 'ID', 'PH', 'MY', 'ZA', 'US', 'TR', 'SA', 'PK'];
      for (final cc in countries) {
        await expectLater(
          ParseAnalyticsService.logParseSuccess(
            countryCode: cc,
            sourcePackage: 'com.android.messaging',
            parserUsed: 'generic',
          ),
          completes,
        );
      }
    });
  });
}
