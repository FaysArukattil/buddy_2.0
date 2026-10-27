// lib/services/preference_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Centralized service to manage, reactively notify, and persist app-wide preferences
/// both locally (SharedPreferences) and in the cloud (Firebase Firestore users/{uid}).
///
/// This ensures preferences like the "On Home" debt calculation and Home Screen mode
/// are never lost when the app is removed, reinstalled, or used across devices.
class PreferenceService {
  PreferenceService._();

  static const String keyIncludeDebts = 'include_debts_in_balance';
  static const String keyHomeBalanceMode = 'home_balance_view_mode';

  /// Reactive notifier for whether loans and debts are reflected on Home Screen.
  static final ValueNotifier<bool> includeDebtsInHomeNotifier =
      ValueNotifier<bool>(true);

  /// Reactive notifier for the user's selected Home Screen balance mode
  /// (0 = Net Balance, 1 = Income only, 2 = Expense only).
  static final ValueNotifier<int> homeBalanceModeNotifier =
      ValueNotifier<int>(0);

  static bool _initialized = false;

  static String? get _currentUserId {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Load preferences from disk first for instant offline startup, then sync with Firestore.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIncludeDebts = prefs.getBool(keyIncludeDebts) ?? true;
      final savedBalanceMode = prefs.getInt(keyHomeBalanceMode) ?? 0;

      includeDebtsInHomeNotifier.value = savedIncludeDebts;
      homeBalanceModeNotifier.value = savedBalanceMode.clamp(0, 2);
      _initialized = true;

      // Sync cloud preferences in background if user is logged in
      syncFromFirestore().catchError((e) {
        debugPrint('⚠️ PreferenceService background cloud sync error: $e');
      });
    } catch (e) {
      debugPrint('⚠️ PreferenceService.init error: $e');
    }
  }

  /// Update the "reflect debts in home screen" preference.
  /// Notifies all listeners immediately, persists to SharedPreferences, and syncs to Firestore.
  static Future<void> setIncludeDebtsInHome(bool value) async {
    includeDebtsInHomeNotifier.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyIncludeDebts, value);
    } catch (e) {
      debugPrint('⚠️ PreferenceService.setIncludeDebtsInHome local error: $e');
    }

    _syncToFirestore(includeDebts: value);
  }

  /// Update the Home Screen balance view mode (0 = Net Balance, 1 = Income, 2 = Expense).
  /// Notifies listeners, saves to SharedPreferences, and syncs to Firestore.
  static Future<void> setHomeBalanceMode(int mode) async {
    final clamped = mode.clamp(0, 2);
    homeBalanceModeNotifier.value = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(keyHomeBalanceMode, clamped);
    } catch (e) {
      debugPrint('⚠️ PreferenceService.setHomeBalanceMode local error: $e');
    }

    _syncToFirestore(homeMode: clamped);
  }

  /// Restore user preferences from Firebase Firestore users/{uid}.
  /// Called on app startup, after login, and during cloud re-initialization.
  static Future<void> syncFromFirestore() async {
    final uid = _currentUserId;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;
      final prefs = await SharedPreferences.getInstance();

      if (data.containsKey('includeDebtsInHome')) {
        final bool remoteVal = data['includeDebtsInHome'] as bool;
        if (includeDebtsInHomeNotifier.value != remoteVal) {
          includeDebtsInHomeNotifier.value = remoteVal;
        }
        await prefs.setBool(keyIncludeDebts, remoteVal);
      }

      if (data.containsKey('homeBalanceMode')) {
        final int remoteMode = (data['homeBalanceMode'] as num).toInt();
        if (homeBalanceModeNotifier.value != remoteMode) {
          homeBalanceModeNotifier.value = remoteMode.clamp(0, 2);
        }
        await prefs.setInt(keyHomeBalanceMode, remoteMode.clamp(0, 2));
      }

      debugPrint(
        '☁️ Preferences restored from Firestore for $uid: includeDebts=${includeDebtsInHomeNotifier.value}, homeMode=${homeBalanceModeNotifier.value}',
      );
    } catch (e) {
      debugPrint('⚠️ PreferenceService.syncFromFirestore error: $e');
    }
  }

  /// Write updated preference key/values to the user's document in Firestore with merge: true.
  static Future<void> _syncToFirestore({bool? includeDebts, int? homeMode}) async {
    final uid = _currentUserId;
    if (uid == null) return;

    try {
      final Map<String, dynamic> updateData = {
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (includeDebts != null) {
        updateData['includeDebtsInHome'] = includeDebts;
      }
      if (homeMode != null) {
        updateData['homeBalanceMode'] = homeMode;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(updateData, SetOptions(merge: true));
      debugPrint('☁️ Successfully synced preferences to Firestore for user $uid');
    } catch (e) {
      debugPrint('⚠️ PreferenceService Firestore sync error (non-critical): $e');
    }
  }

  /// Helper to check current values synchronously
  static bool get includeDebtsInHome => includeDebtsInHomeNotifier.value;
  static int get homeBalanceMode => homeBalanceModeNotifier.value;
  static bool get isInitialized => _initialized;
}
