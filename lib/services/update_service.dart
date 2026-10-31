// lib/services/update_service.dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Handles forced and prompted app updates using two mechanisms:
///
/// 1. **Play Core in-app update** (`in_app_update` package) — native Play Store
///    update flow. Skipped for debug builds and non-Play-Store installs.
/// 2. **Firebase Remote Config** — server-side version control with keys:
///    - `min_supported_version`: versions below this get a blocking dialog
///    - `latest_version`: versions below this get a soft dismissible prompt
///    - `force_update`: bool override to force an immediate update
///    - `update_message`: custom message shown in the update dialog
///
/// All checks are wrapped in try/catch and never block or crash the app.
class UpdateService {
  UpdateService._();

  // ── In-memory guards ──
  static bool _isDialogShowing = false;
  static bool _hasCheckedThisSession = false;

  // ── SharedPreferences key ──
  static const String _keyLastSoftPromptDate = 'last_update_prompt_date';

  // ── Play Store listing URL ──
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.faysarukattil.buddy';

  /// Run the full update check. Safe to call from splash, app start, and resume.
  /// Never throws, never blocks the app.
  static Future<void> checkForUpdate(BuildContext context) async {
    // Skip on non-Android platforms
    if (kIsWeb || !Platform.isAndroid) return;

    // Prevent concurrent dialog triggers
    if (_isDialogShowing) return;

    try {
      // 1. Get current installed version
      final packageInfo = await PackageInfo.fromPlatform();
      final installedVersion = packageInfo.version; // e.g. "17.1.0"
      final installedBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 2. Fetch Remote Config
      final remoteConfig = FirebaseRemoteConfig.instance;
      await _initRemoteConfig(remoteConfig);

      final minSupportedVersion =
          remoteConfig.getString('min_supported_version');
      final latestVersion = remoteConfig.getString('latest_version');
      final forceUpdate = remoteConfig.getBool('force_update');
      final updateMessage = remoteConfig.getString('update_message');

      debugPrint(
        '🔄 UPDATE: installed=$installedVersion+$installedBuild, '
        'min=$minSupportedVersion, latest=$latestVersion, '
        'force=$forceUpdate',
      );

      // 3. Check if force update is needed
      if (forceUpdate ||
          (minSupportedVersion.isNotEmpty &&
              _isVersionLower(installedVersion, minSupportedVersion))) {
        // BLOCKING: version is critically old
        if (!context.mounted) return;
        await _showForceUpdateDialog(context, updateMessage);
        return;
      }

      // 4. Check if soft update is available
      if (latestVersion.isNotEmpty &&
          _isVersionLower(installedVersion, latestVersion)) {
        // Respect once-per-day limit for soft updates
        if (await _wasSoftPromptShownToday()) {
          debugPrint('🔄 UPDATE: Soft prompt already shown today, skipping');
          return;
        }

        // Try Play Core in-app update first (only for Play Store installs)
        if (!kDebugMode && await _isInstalledFromPlayStore()) {
          try {
            final updateInfo = await InAppUpdate.checkForUpdate();
            if (updateInfo.updateAvailability ==
                UpdateAvailability.updateAvailable) {
              // Use flexible update by default
              await InAppUpdate.startFlexibleUpdate();
              await InAppUpdate.completeFlexibleUpdate();
              await _markSoftPromptShown();
              debugPrint('✅ UPDATE: Flexible in-app update started');
              return;
            }
          } catch (e) {
            debugPrint('⚠️ UPDATE: In-app update failed, falling back: $e');
          }
        }

        // Fallback: show a dismissible dialog
        if (!context.mounted) return;
        await _showSoftUpdateDialog(context, updateMessage);
        await _markSoftPromptShown();
        return;
      }

      debugPrint('✅ UPDATE: App is up to date');
    } catch (e) {
      // Silent failure — never block the app
      debugPrint('⚠️ UPDATE: Check failed (non-critical): $e');
    }
  }

  /// Check on app resume — lighter version that respects session guard.
  static Future<void> checkOnResume(BuildContext context) async {
    if (_isDialogShowing) return;
    // Only re-check if we haven't already checked this session
    // (avoids repeated checks on quick background/foreground cycles)
    if (_hasCheckedThisSession) return;
    await checkForUpdate(context);
  }

  // ── Remote Config ──

  static bool _remoteConfigInitialized = false;

  static Future<void> _initRemoteConfig(
    FirebaseRemoteConfig remoteConfig,
  ) async {
    try {
      if (!_remoteConfigInitialized) {
        // Set in-app defaults so the app works fully offline and on first launch
        await remoteConfig.setDefaults({
          'min_supported_version': '1.0.0',
          'latest_version': '',
          'force_update': false,
          'update_message': '',
        });

        await remoteConfig.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode
              ? const Duration(seconds: 60)
              : const Duration(hours: 12),
        ));

        _remoteConfigInitialized = true;
      }

      // Attempt to fetch and activate — fails silently if offline
      await remoteConfig.fetchAndActivate().timeout(
            const Duration(seconds: 10),
            onTimeout: () => false,
          );
    } catch (e) {
      debugPrint('⚠️ UPDATE: Remote Config fetch error (using defaults): $e');
    }
  }

  // ── Version Comparison ──

  /// Compare versions numerically, segment by segment.
  /// Returns true if [installed] is strictly lower than [required].
  /// Examples: "1.9.0" < "1.10.0" → true, "17.1.0" < "17.1.0" → false
  static bool _isVersionLower(String installed, String required) {
    try {
      final installedParts = installed.split('.').map(_parseInt).toList();
      final requiredParts = required.split('.').map(_parseInt).toList();

      // Pad shorter list with zeros
      final maxLen = installedParts.length > requiredParts.length
          ? installedParts.length
          : requiredParts.length;

      while (installedParts.length < maxLen) {
        installedParts.add(0);
      }
      while (requiredParts.length < maxLen) {
        requiredParts.add(0);
      }

      for (int i = 0; i < maxLen; i++) {
        if (installedParts[i] < requiredParts[i]) return true;
        if (installedParts[i] > requiredParts[i]) return false;
      }

      return false; // versions are equal
    } catch (e) {
      debugPrint('⚠️ UPDATE: Version comparison error: $e');
      return false; // fail safe — don't force update on parse error
    }
  }

  static int _parseInt(String s) => int.tryParse(s.trim()) ?? 0;

  // ── Play Store Install Check ──

  /// Returns true if the app was installed from the Google Play Store.
  static Future<bool> _isInstalledFromPlayStore() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final installer = packageInfo.installerStore ?? '';
      return installer == 'com.android.vending' ||
          installer == 'com.google.android.feedback';
    } catch (e) {
      debugPrint('⚠️ UPDATE: Could not determine installer: $e');
      return false;
    }
  }

  // ── Daily Limit ──

  static Future<bool> _wasSoftPromptShownToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDateStr = prefs.getString(_keyLastSoftPromptDate);
      if (lastDateStr == null) return false;

      final lastDate = DateTime.tryParse(lastDateStr);
      if (lastDate == null) return false;

      final now = DateTime.now();
      return lastDate.year == now.year &&
          lastDate.month == now.month &&
          lastDate.day == now.day;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markSoftPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyLastSoftPromptDate,
        DateTime.now().toIso8601String(),
      );
    } catch (_) {}
  }

  // ── Dialogs ──

  /// Blocking dialog — cannot be dismissed, only "Update" button.
  static Future<void> _showForceUpdateDialog(
    BuildContext context,
    String message,
  ) async {
    if (_isDialogShowing || !context.mounted) return;
    _isDialogShowing = true;
    _hasCheckedThisSession = true;

    final displayMessage = message.isNotEmpty
        ? message
        : 'This version of Buddy is no longer supported. Please update to continue using the app.';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.system_update_rounded, size: 28),
              SizedBox(width: 10),
              Text('Update Required'),
            ],
          ),
          content: Text(displayMessage),
          actions: [
            FilledButton.icon(
              onPressed: () => _openPlayStore(),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );

    // If we get here the dialog was somehow dismissed (shouldn't happen)
    _isDialogShowing = false;
  }

  /// Soft update dialog — dismissible with "Later" option.
  static Future<void> _showSoftUpdateDialog(
    BuildContext context,
    String message,
  ) async {
    if (_isDialogShowing || !context.mounted) return;
    _isDialogShowing = true;
    _hasCheckedThisSession = true;

    final displayMessage = message.isNotEmpty
        ? message
        : 'A new version of Buddy is available with improvements and bug fixes.';

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.update_rounded, size: 28),
            SizedBox(width: 10),
            Text('Update Available'),
          ],
        ),
        content: Text(displayMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openPlayStore();
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Update'),
          ),
        ],
      ),
    );

    _isDialogShowing = false;
  }

  /// Open the Play Store listing for this app.
  static Future<void> _openPlayStore() async {
    try {
      final uri = Uri.parse(_playStoreUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('⚠️ UPDATE: Could not open Play Store: $e');
    }
  }

  /// Expose for testing: reset all state.
  @visibleForTesting
  static void resetForTesting() {
    _isDialogShowing = false;
    _hasCheckedThisSession = false;
    _remoteConfigInitialized = false;
  }
}

