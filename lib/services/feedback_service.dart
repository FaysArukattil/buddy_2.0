import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_snackbar.dart';

class FeedbackService {
  static const String developerEmail = 'faysarukattil@gmail.com';

  static String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// Retrieves current installed app version information dynamically.
  static Future<Map<String, String>> getAppInfo() async {
    String version = '1.0.0';
    String buildNumber = '';
    String appName = 'Buddy';

    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        version = info.version;
      }
      buildNumber = info.buildNumber;
      if (info.appName.isNotEmpty) {
        appName = info.appName;
      }
    } catch (e) {
      debugPrint('Notice: package_info_plus fallback: $e');
    }

    String osInfo = 'Unknown';
    try {
      osInfo = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {}

    return {
      'version': version,
      'buildNumber': buildNumber,
      'appName': appName,
      'os': osInfo,
    };
  }

  /// Returns a clean display string for the app version (e.g. "v12.0.0" or "v12.0.0 (Build 12)")
  static Future<String> getAppVersionDisplay({bool includeBuild = false}) async {
    final info = await getAppInfo();
    final version = info['version'] ?? '1.0.0';
    final buildNumber = info['buildNumber'] ?? '';
    if (includeBuild && buildNumber.isNotEmpty) {
      return 'v$version+$buildNumber';
    }
    return 'v$version';
  }

  /// Opens the user's email client to report a bug with the current installed version and device specs.
  static Future<void> reportBug(BuildContext context) async {
    final info = await getAppInfo();
    final version = info['version']!;
    final buildNumber = info['buildNumber']!;
    final os = info['os']!;

    final versionLabel =
        buildNumber.isNotEmpty ? 'v$version (Build $buildNumber)' : 'v$version';
    final subject = '[Bug Report] Buddy App $versionLabel';
    final body = '''Hi Developer,

I found a bug in Buddy App:

[Describe what happened and what you expected to happen]

Steps to reproduce:
1. 
2. 
3. 

Device / OS: $os
App Version: $version${buildNumber.isNotEmpty ? '+$buildNumber' : ''}
''';

    if (!context.mounted) return;
    await _sendEmail(
      context: context,
      subject: subject,
      body: body,
      actionTitle: 'Bug Report',
    );
  }

  /// Opens the user's email client to request a new feature.
  static Future<void> requestFeature(BuildContext context) async {
    final info = await getAppInfo();
    final version = info['version']!;
    final buildNumber = info['buildNumber']!;

    final versionLabel =
        buildNumber.isNotEmpty ? 'v$version (Build $buildNumber)' : 'v$version';
    final subject = '[Feature Request] Buddy App $versionLabel';
    final body = '''Hi Developer,

I would love to see a new feature in Buddy App:

[Describe the feature you want]

Why it would be helpful:
[Explain how it will improve your experience]

App Version: $version${buildNumber.isNotEmpty ? '+$buildNumber' : ''}
''';

    if (!context.mounted) return;
    await _sendEmail(
      context: context,
      subject: subject,
      body: body,
      actionTitle: 'Feature Request',
    );
  }

  /// Builds the mailto Uri with encoded query parameters.
  static Uri createMailUri({
    required String subject,
    required String body,
  }) {
    return Uri(
      scheme: 'mailto',
      path: developerEmail,
      query: _encodeQueryParameters(<String, String>{
        'subject': subject,
        'body': body,
      }),
    );
  }

  static Future<void> _sendEmail({
    required BuildContext context,
    required String subject,
    required String body,
    required String actionTitle,
  }) async {
    final Uri emailLaunchUri = createMailUri(
      subject: subject,
      body: body,
    );

    try {
      final launched = await launchUrl(
        emailLaunchUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        _showFallbackDialog(context, actionTitle, subject, body);
      }
    } catch (e) {
      debugPrint('Error launching email client: $e');
      if (context.mounted) {
        _showFallbackDialog(context, actionTitle, subject, body);
      }
    }
  }

  static void _showFallbackDialog(
    BuildContext context,
    String actionTitle,
    String subject,
    String body,
  ) {
    Clipboard.setData(const ClipboardData(text: developerEmail));
    AppSnackbar.showInfo(
      context,
      'No mail app found. Dev email ($developerEmail) copied to clipboard!',
      duration: const Duration(seconds: 4),
    );
  }
}
