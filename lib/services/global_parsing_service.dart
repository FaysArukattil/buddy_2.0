// lib/services/global_parsing_service.dart
//
// Manages the Remote Config flags for global (non-India) native notification
// parsing and writes them to SharedPreferences so the Kotlin
// NotificationListener can read them even when the Flutter app is closed.
//
// Remote Config keys:
//   enable_global_native_parsing  (bool, default false)
//   global_parsing_countries      (String, comma-separated ISO-3166-1 alpha-2
//                                  codes e.g. "AE,SA,NG,KE"; empty = all)
//   global_parsing_rules_json     (String, updated bank_rules.json content;
//                                  empty = use bundled asset)

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'currency_service.dart';
import '../parsing/parser_registry.dart';

class GlobalParsingService {
  // SharedPreferences keys — must match GlobalParserRegistry constants in Kotlin
  static const _keyEnabled = 'flutter.enable_global_native_parsing';
  static const _keyCountries = 'flutter.global_parsing_countries';
  static const _keyRulesJson = 'flutter.global_parsing_rules_json';

  // Remote Config keys
  static const _rcKeyEnabled = 'enable_global_native_parsing';
  static const _rcKeyCountries = 'global_parsing_countries';
  static const _rcKeyRulesJson = 'global_parsing_rules_json';

  static bool _initialized = false;

  /// Fetch Remote Config flags, write them to SharedPreferences, and
  /// optionally reload the Dart ParserRegistry with any updated rules.
  ///
  /// Safe to call from [app_init_helper.dart] after Firebase is ready.
  /// Fails silently — never throws.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final rc = FirebaseRemoteConfig.instance;

      // Set in-app defaults so offline behaviour is well-defined
      await rc.setDefaults({
        _rcKeyEnabled: false,
        _rcKeyCountries: '',
        _rcKeyRulesJson: '',
      });

      // Attempt to fetch (may fail offline — already handled by UpdateService)
      try {
        await rc.fetchAndActivate().timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        );
      } catch (_) {
        // Offline or fetch error — use whatever is cached / defaulted
      }

      final enabled = rc.getBool(_rcKeyEnabled);
      final countries = rc.getString(_rcKeyCountries);
      final rulesJson = rc.getString(_rcKeyRulesJson);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, enabled);
      await prefs.setString(_keyCountries, countries);

      // Only write the rules JSON to SharedPrefs if it's non-empty and valid
      if (rulesJson.isNotEmpty) {
        await prefs.setString(_keyRulesJson, rulesJson);
        // Reload the Dart registry with the Remote Config rules
        try {
          await ParserRegistry.instance.reloadFromRemoteConfig(rulesJson);
          debugPrint('✅ GlobalParsingService: ParserRegistry reloaded from Remote Config');
        } catch (e) {
          debugPrint('⚠️ GlobalParsingService: Remote Config rules invalid, keeping bundled: $e');
        }
      }

      debugPrint(
        '✅ GlobalParsingService: enabled=$enabled '
        'countries="${countries.isEmpty ? "all" : countries}" '
        'rulesJson=${rulesJson.isNotEmpty ? "${rulesJson.length} bytes" : "bundled"}',
      );
    } catch (e) {
      debugPrint('⚠️ GlobalParsingService.initialize failed (non-critical): $e');
    }
  }

  /// Whether global native parsing is enabled for the current user's country.
  ///
  /// Returns false if:
  ///   - the user's country is IN (India — handled by the hardcoded Kotlin parser)
  ///   - the RC flag is off
  ///   - the user's country is not in the allowed list (when list is non-empty)
  static Future<bool> isEnabledForCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_keyEnabled) ?? false;
      if (!enabled) return false;

      final userCountry = CurrencyService.countryCode.toUpperCase();
      if (userCountry == 'IN') return false;

      final countries = prefs.getString(_keyCountries) ?? '';
      if (countries.isBlank) return true; // empty = all countries

      final allowed = countries.split(',').map((c) => c.trim().toUpperCase()).toSet();
      return allowed.contains(userCountry);
    } catch (_) {
      return false;
    }
  }
}

extension _StringBlank on String {
  bool get isBlank => trim().isEmpty;
}

