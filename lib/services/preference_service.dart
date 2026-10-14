// lib/services/preference_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized service to manage and reactively notify app-wide preferences.
class PreferenceService {
  PreferenceService._();

  static const String keyIncludeDebts = 'include_debts_in_balance';

  /// Reactive notifier for whether loans and debts are reflected on Home Screen.
  static final ValueNotifier<bool> includeDebtsInHomeNotifier =
      ValueNotifier<bool>(true);

  static bool _initialized = false;

  /// Load preferences from disk and initialize notifiers
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVal = prefs.getBool(keyIncludeDebts) ?? true;
      includeDebtsInHomeNotifier.value = savedVal;
      _initialized = true;
    } catch (e) {
      debugPrint('⚠️ PreferenceService.init error: $e');
    }
  }

  /// Update the "reflect debts in home screen" preference and notify all listeners immediately
  static Future<void> setIncludeDebtsInHome(bool value) async {
    includeDebtsInHomeNotifier.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyIncludeDebts, value);
    } catch (e) {
      debugPrint('⚠️ PreferenceService.setIncludeDebtsInHome error: $e');
    }
  }

  /// Helper to check current value synchronously
  static bool get includeDebtsInHome => includeDebtsInHomeNotifier.value;
  static bool get isInitialized => _initialized;
}
