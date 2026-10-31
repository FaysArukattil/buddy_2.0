import 'dart:convert';
import 'package:flutter/services.dart';
import 'bank_parser.dart';
import 'generic_parser.dart';

/// Loads [bank_rules.json], validates it, and routes notifications to the
/// correct country parser.
///
/// Singleton — call [ParserRegistry.instance] everywhere.
///
/// India (IN) is intentionally omitted from this registry: the Kotlin
/// [NotificationListener] handles all India parsing with its own hardcoded
/// logic which has been in production and is regression-tested. The Dart
/// [ParserRegistry] only handles countries other than India for the
/// secondary Dart-side sync path and for users outside India.
class ParserRegistry {
  ParserRegistry._();
  static final ParserRegistry _instance = ParserRegistry._();
  static ParserRegistry get instance => _instance;

  // country-code → parser
  final Map<String, BankParser> _parsers = {};
  bool _loaded = false;

  /// Load rules from the bundled asset. Safe to call multiple times.
  Future<void> initialize() async {
    if (_loaded) return;
    try {
      final jsonStr =
          await rootBundle.loadString('assets/parsing/bank_rules.json');
      _loadFromJson(jsonStr);
      _loaded = true;
    } catch (e) {
      // Non-fatal — app works without the registry (India path is unaffected)
      _loaded = true; // don't retry on every call
      assert(() {
        // ignore: avoid_print
        print('⚠️ ParserRegistry: failed to load bank_rules.json — $e');
        return true;
      }());
    }
  }

  /// Reload rules from a Remote-Config-supplied JSON string.
  /// Falls back to the bundled asset if [json] is invalid.
  Future<void> reloadFromRemoteConfig(String json) async {
    try {
      _loadFromJson(json);
    } catch (_) {
      // Invalid remote JSON — keep the bundled rules already loaded.
    }
  }

  void _loadFromJson(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    // Basic schema validation
    if (!data.containsKey('rules') || data['rules'] is! List) {
      throw const FormatException('bank_rules.json missing "rules" array');
    }

    final rules = data['rules'] as List<dynamic>;
    final newParsers = <String, BankParser>{};

    for (final rule in rules) {
      if (rule is! Map<String, dynamic>) continue;
      final country = (rule['country'] as String?)?.toUpperCase();
      if (country == null || country == 'IN') continue; // Skip India entry

      // Required fields guard
      final currencyCode = rule['currencyCode'] as String?;
      if (currencyCode == null) continue;

      final parser = GenericParser.fromRule(rule);
      newParsers[country] = parser;
    }

    _parsers
      ..clear()
      ..addAll(newParsers);
  }

  /// Parse a notification for [countryCode].
  ///
  /// Returns `null` if:
  ///   - [countryCode] is 'IN' (Kotlin handles it)
  ///   - No parser is registered for [countryCode]
  ///   - The message doesn't match a transaction
  ParsedTransaction? parse(
    String text,
    String sourcePackage,
    String countryCode,
  ) {
    if (countryCode.toUpperCase() == 'IN') return null;
    final parser = _parsers[countryCode.toUpperCase()];
    if (parser == null) return null;
    return parser.parse(text, sourcePackage);
  }

  /// Whether a parser is registered for [countryCode].
  bool supports(String countryCode) =>
      countryCode.toUpperCase() != 'IN' &&
      _parsers.containsKey(countryCode.toUpperCase());

  /// All supported country codes (excluding IN).
  Iterable<String> get supportedCountries => _parsers.keys;

  int get ruleCount => _parsers.length;
}

