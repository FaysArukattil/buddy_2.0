// ignore_for_file: file_names

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_init_helper.dart';

class NetworkHelper {
  /// Reactive notifier for real-time offline/online UI updates across the entire app
  static final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  static Timer? _monitorTimer;
  static bool _isChecking = false;

  static bool get isConnected => isOnline.value;

  /// Check if device has internet connectivity (comprehensive check)
  static Future<bool> hasInternetConnection() async {
    return checkConnection();
  }

  /// Quick connectivity check
  static Future<bool> quickConnectivityCheck() async {
    return checkConnection(timeout: const Duration(milliseconds: 1800));
  }

  /// Active connection verification with short timeout and fallback
  static Future<bool> checkConnection({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (kIsWeb) {
      isOnline.value = true;
      return true;
    }

    try {
      final result =
          await InternetAddress.lookup('google.com').timeout(timeout);
      final connected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _updateStatus(connected);
      return connected;
    } on SocketException catch (_) {
      _updateStatus(false);
      return false;
    } on TimeoutException catch (_) {
      _updateStatus(false);
      return false;
    } catch (_) {
      _updateStatus(false);
      return false;
    }
  }

  static void _updateStatus(bool connected) {
    if (isOnline.value != connected) {
      final wasOffline = !isOnline.value;
      isOnline.value = connected;
      debugPrint(
        '🌐 NETWORK: Connectivity status changed -> ${connected ? "ONLINE 🟢" : "OFFLINE 📶"}',
      );

      if (wasOffline && connected) {
        // Trigger sync of any transactions saved or updated while offline
        try {
          AppInitHelper.syncNow();
        } catch (e) {
          debugPrint('⚠️ Auto-sync on network restore failed: $e');
        }
      }
    }
  }

  /// Start background periodic network monitoring (checks every 5 seconds)
  static void startMonitoring() {
    _monitorTimer?.cancel();
    // Immediate initial check
    checkConnection();

    _monitorTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isChecking) return;
      _isChecking = true;
      try {
        await checkConnection(timeout: const Duration(seconds: 2));
      } finally {
        _isChecking = false;
      }
    });
    debugPrint('🌐 NETWORK: Monitoring active');
  }

  /// Stop monitoring
  static void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    debugPrint('🌐 NETWORK: Monitoring stopped');
  }
}
