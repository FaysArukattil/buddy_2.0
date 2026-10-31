import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:buddy/parsing/generic_parser.dart';
import 'package:buddy/parsing/bank_parser.dart';

/// Dart-side regression tests using the shared test vectors file.
///
/// These tests run against [GenericParser] (all non-India countries).
/// India vectors (IN_*) are represented only as schema checks here
/// because India parsing lives in Kotlin's NotificationListener.kt and
/// is regression-tested by BankSmsParserTest.kt.
///
/// ALL non-India vectors must pass before any parser changes.
void main() {
  // Load data synchronously before any group() call so the for-loops
  // that build test cases can access it at collection time.
  final rulesFile = File('assets/parsing/bank_rules.json');
  final bankRules =
      jsonDecode(rulesFile.readAsStringSync()) as Map<String, dynamic>;

  final vectorsFile = File('test/parsing/bank_sms_test_vectors.json');
  final vectorsData =
      jsonDecode(vectorsFile.readAsStringSync()) as Map<String, dynamic>;
  final vectors = (vectorsData['vectors'] as List).cast<Map<String, dynamic>>();

  // ── Helper: build a GenericParser for a country from the loaded rules ──
  GenericParser? buildParser(String countryCode) {
    final rules = (bankRules['rules'] as List).cast<Map<String, dynamic>>();
    final rule =
        rules.where((r) => r['country'] == countryCode).firstOrNull;
    if (rule == null || countryCode == 'IN') return null;
    return GenericParser.fromRule(rule);
  }

  // ── bank_rules.json schema tests ──────────────────────────────────────
  group('bank_rules.json schema validation', () {
    test('file is valid JSON with required top-level fields', () {
      expect(bankRules['version'], isNotNull);
      expect(bankRules['rules'], isA<List>());
    });

    test('every rule has required fields', () {
      final rules = (bankRules['rules'] as List).cast<Map<String, dynamic>>();
      for (final rule in rules) {
        expect(rule['country'], isA<String>(),
            reason: 'Rule missing "country": $rule');
        expect(rule['currencyCode'], isA<String>(),
            reason:
                'Rule missing "currencyCode" for ${rule["country"]}');
        expect(rule['currencySymbol'], isA<String>(),
            reason:
                'Rule missing "currencySymbol" for ${rule["country"]}');
      }
    });

    test('India entry exists for documentation purposes', () {
      final rules = (bankRules['rules'] as List).cast<Map<String, dynamic>>();
      final indiaRule =
          rules.where((r) => r['country'] == 'IN').firstOrNull;
      expect(indiaRule, isNotNull);
    });

    test('at least 20 country rules are defined', () {
      final rules = (bankRules['rules'] as List);
      expect(rules.length, greaterThanOrEqualTo(20));
    });
  });

  // ── Test-vector schema tests ───────────────────────────────────────────
  group('Test vectors schema', () {
    test('vectors file has at least 30 entries', () {
      expect(vectors.length, greaterThanOrEqualTo(30));
    });

    test('every vector has required fields', () {
      for (final v in vectors) {
        expect(v['id'], isA<String>(),
            reason: 'Vector missing id: $v');
        expect(v['country'], isA<String>(),
            reason: 'Vector missing country: $v');
        expect(v['message'], isA<String>(),
            reason: 'Vector ${v["id"]} missing message');
        expect(v['sourcePackage'], isA<String>(),
            reason: 'Vector ${v["id"]} missing sourcePackage');
        expect(v['shouldIgnore'], isA<bool>(),
            reason: 'Vector ${v["id"]} missing shouldIgnore');
      }
    });

    test('India vectors exist', () {
      final indiaVectors = vectors.where((v) => v['country'] == 'IN').toList();
      expect(indiaVectors.length, greaterThanOrEqualTo(6));
    });

    // India vectors — schema-only; actual parsing tested in Kotlin
    for (final vector in vectors.where((v) => v['country'] == 'IN')) {
      test('[${vector['id']}] India vector schema valid (Kotlin parses these)',
          () {
        expect(vector['id'], isNotNull);
        expect(vector['message'], isA<String>());
        expect(
          vector['expectedType'],
          anyOf(isNull, equals('expense'), equals('income')),
        );
      });
    }
  });

  // ── Pakistan (PK) ─────────────────────────────────────────────────────
  group('Pakistan (PK) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('PK');
      expect(p, isNotNull, reason: 'PK parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'PK')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── UAE (AE) ──────────────────────────────────────────────────────────
  group('UAE (AE) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('AE');
      expect(p, isNotNull, reason: 'AE parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'AE')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Nigeria (NG) ──────────────────────────────────────────────────────
  group('Nigeria (NG) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('NG');
      expect(p, isNotNull, reason: 'NG parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'NG')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Kenya (KE) ────────────────────────────────────────────────────────
  group('Kenya (KE) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('KE');
      expect(p, isNotNull, reason: 'KE parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'KE')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── UK (GB) ───────────────────────────────────────────────────────────
  group('UK (GB) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('GB');
      expect(p, isNotNull, reason: 'GB parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'GB')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Germany (DE) ──────────────────────────────────────────────────────
  group('Germany (DE) parser — European decimal format', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('DE');
      expect(p, isNotNull, reason: 'DE parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'DE')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Brazil (BR) ───────────────────────────────────────────────────────
  group('Brazil (BR) parser — R\$ with dot-thousands/comma-decimal', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('BR');
      expect(p, isNotNull, reason: 'BR parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'BR')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Indonesia (ID) ────────────────────────────────────────────────────
  group('Indonesia (ID) parser — Rp dot-thousands zero-decimal', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('ID');
      expect(p, isNotNull, reason: 'ID parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'ID')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Philippines (PH) ──────────────────────────────────────────────────
  group('Philippines (PH) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('PH');
      expect(p, isNotNull, reason: 'PH parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'PH')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Malaysia (MY) ─────────────────────────────────────────────────────
  group('Malaysia (MY) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('MY');
      expect(p, isNotNull, reason: 'MY parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'MY')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── South Africa (ZA) ─────────────────────────────────────────────────
  group('South Africa (ZA) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('ZA');
      expect(p, isNotNull, reason: 'ZA parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'ZA')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── USA (US) ──────────────────────────────────────────────────────────
  group('USA (US) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('US');
      expect(p, isNotNull, reason: 'US parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'US')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Turkey (TR) ───────────────────────────────────────────────────────
  group('Turkey (TR) parser — European decimal ₺', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('TR');
      expect(p, isNotNull, reason: 'TR parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'TR')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Saudi Arabia (SA) ─────────────────────────────────────────────────
  group('Saudi Arabia (SA) parser', () {
    late GenericParser parser;
    setUpAll(() {
      final p = buildParser('SA');
      expect(p, isNotNull, reason: 'SA parser not in bank_rules.json');
      parser = p!;
    });
    for (final v in vectors.where((v) => v['country'] == 'SA')) {
      test('[${v['id']}] ${v['description']}', () {
        runVectorTest(parser, v);
      });
    }
  });

  // ── Amount parsing edge cases ─────────────────────────────────────────
  group('GenericParser amount parsing edge cases', () {
    test('European format 1.234,56 € is parsed as 1234.56', () {
      final parser = buildParser('DE')!;
      final result = parser.parse(
        'DKB: Ihre Karte XXXX1234 wurde am 31.10.2026 mit 1.234,56 € belastet. '
        'Verfügbarer Betrag: 5.000,00 €.',
        'com.google.android.apps.messaging',
      );
      expect(result, isNotNull);
      expect(result!.amount, closeTo(1234.56, 0.02));
    });

    test('Indonesian IDR Rp50.000 is parsed as 50000', () {
      final parser = buildParser('ID')!;
      final result = parser.parse(
        'GoPay: Kamu membayar Rp50.000 ke Gojek Driver. Saldo GoPay: Rp150.000.',
        'com.gojek.app',
      );
      expect(result, isNotNull);
      expect(result!.amount, closeTo(50000.0, 1.0));
    });

    test('OTP message returns null for any country', () {
      final parser = buildParser('AE')!;
      final result = parser.parse(
        'Your Emirates NBD OTP is 123456. Valid for 5 minutes.',
        'com.google.android.apps.messaging',
      );
      expect(result, isNull);
    });

    test('Failed transaction returns null', () {
      final parser = buildParser('GB')!;
      final result = parser.parse(
        'Barclays: Your payment of £250.00 has failed. Please try again.',
        'com.google.android.apps.messaging',
      );
      expect(result, isNull);
    });

    test('Balance amount not mistaken for transaction amount', () {
      final parser = buildParser('AE')!;
      // Only balance mentioned — no debit/credit verb
      final result = parser.parse(
        'Emirates NBD: Your account XXXX1234. Available Balance: AED 10,000.00.',
        'com.google.android.apps.messaging',
      );
      // No debit/credit verb → should return null
      expect(result, isNull);
    });
  });
}

/// Runs one test vector assertion against [parser].
void runVectorTest(BankParser parser, Map<String, dynamic> vector) {
  final message = vector['message'] as String;
  final sourcePackage = vector['sourcePackage'] as String;
  final shouldIgnore = vector['shouldIgnore'] as bool;
  final expectedType = vector['expectedType'] as String?;
  final expectedAmount = (vector['expectedAmount'] as num?)?.toDouble();
  final expectedCurrency = vector['expectedCurrency'] as String?;

  final result = parser.parse(message, sourcePackage);

  if (shouldIgnore) {
    expect(
      result,
      isNull,
      reason: '[${vector['id']}] Should be IGNORED but got: $result\n'
          'Message: $message',
    );
    return;
  }

  expect(
    result,
    isNotNull,
    reason: '[${vector['id']}] Should be PARSED but got null.\n'
        'Message: $message',
  );

  if (expectedType != null) {
    expect(
      result!.type,
      equals(expectedType),
      reason: '[${vector['id']}] Wrong type: '
          'expected "$expectedType" got "${result.type}"',
    );
  }

  if (expectedAmount != null) {
    expect(
      result!.amount,
      closeTo(expectedAmount, 0.02),
      reason: '[${vector['id']}] Wrong amount: '
          'expected $expectedAmount got ${result.amount}',
    );
  }

  if (expectedCurrency != null) {
    expect(
      result!.currencyCode,
      equals(expectedCurrency),
      reason: '[${vector['id']}] Wrong currency: '
          'expected "$expectedCurrency" got "${result.currencyCode}"',
    );
  }
}
