// ignore_for_file: file_names

import 'dart:io';

class NetworkHelper {
  // Check if device has internet connectivity
  static Future<bool> hasInternetConnection() async {
    try {
      // Try to lookup Google's DNS
      final result = await InternetAddress.lookup('google.com');

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
      return false;
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  // Quick connectivity check (faster but less reliable)
  static Future<bool> quickConnectivityCheck() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
