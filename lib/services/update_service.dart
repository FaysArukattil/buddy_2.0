// lib/services/update_service.dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// Handles non-intrusive Google Play Store in-app updates.
///
/// Whenever an update is available on the Google Play Store and the user opens
/// or resumes the app:
/// 1. Queries Google Play directly via the official Play Core API.
/// 2. If an update is available, Google Play displays its native bottom-sheet card popup
///    with "Update" and "No thanks" options.
/// 3. If accepted, the update downloads in the background while the user continues
///    using the app without any forced interruptions or blocking walls.
/// 4. Requires ZERO configuration in Firebase Remote Config.
///
/// All checks are wrapped in try/catch and never block or crash the app.
class UpdateService {
  UpdateService._();

  static bool _isChecking = false;
  static bool _hasCheckedThisSession = false;

  /// Check for update directly from Google Play Store.
  /// Shows Google Play's official native card popup whenever an update is available.
  /// Safe to call on app launch and resume. Never blocks the app.
  static Future<void> checkForUpdate([BuildContext? context]) async {
    // In-app updates are exclusive to Android
    if (kIsWeb || !Platform.isAndroid) return;
    if (_isChecking) return;
    _isChecking = true;

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      debugPrint(
        '🔄 PLAY UPDATE: availability=${updateInfo.updateAvailability}, '
        'flexibleAllowed=${updateInfo.flexibleUpdateAllowed}',
      );

      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        if (updateInfo.flexibleUpdateAllowed) {
          // Triggers Google Play's native bottom-sheet card popup
          debugPrint('🚀 PLAY UPDATE: Prompting Google Play flexible update card...');
          final result = await InAppUpdate.startFlexibleUpdate();
          debugPrint('✅ PLAY UPDATE: Flexible update completed with result: $result');

          if (result == AppUpdateResult.success) {
            // Install the downloaded update
            await InAppUpdate.completeFlexibleUpdate();
          }
        } else if (updateInfo.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        }
      } else {
        debugPrint('✅ PLAY UPDATE: App is up to date on Google Play');
      }
    } catch (e) {
      // Normal when run in debug mode, sideloaded via ADB, or when device is offline
      debugPrint('ℹ️ PLAY UPDATE: In-app update check skipped: $e');
    } finally {
      _isChecking = false;
      _hasCheckedThisSession = true;
    }
  }

  /// Check on app resume — checks once per foreground session.
  static Future<void> checkOnResume(BuildContext context) async {
    if (_hasCheckedThisSession) return;
    await checkForUpdate(context);
  }

  /// Reset state for testing.
  @visibleForTesting
  static void resetForTesting() {
    _isChecking = false;
    _hasCheckedThisSession = false;
  }
}
