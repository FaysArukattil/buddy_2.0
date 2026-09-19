import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class FeedbackService {
  static const String developerEmail = 'faysarukattil@gmail.com';

  static String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// Opens the user's email client to report a bug.
  static Future<void> reportBug(BuildContext context) async {
    const String subject = '[Bug Report] Buddy App v1.0.0';
    const String body = '''Hi Developer,

I found a bug in Buddy App:

[Describe what happened and what you expected to happen]

Steps to reproduce:
1. 
2. 
3. 

Device / Android Version: 
App Version: 1.0.0
''';

    await _sendEmail(
      context: context,
      subject: subject,
      body: body,
      actionTitle: 'Bug Report',
    );
  }

  /// Opens the user's email client to request a new feature.
  static Future<void> requestFeature(BuildContext context) async {
    const String subject = '[Feature Request] Buddy App';
    const String body = '''Hi Developer,

I would love to see a new feature in Buddy App:

[Describe the feature you want]

Why it would be helpful:
[Explain how it will improve your experience]
''';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No mail app found. Dev email ($developerEmail) copied to clipboard!',
        ),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
