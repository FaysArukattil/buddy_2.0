import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:buddy/utils/app_snackbar.dart';

class LegalService {
  static const String privacyPolicyUrl =
      'https://faysarukattil.github.io/buddy_2.0/privacy.html';
  static const String termsUrl =
      'https://faysarukattil.github.io/buddy_2.0/terms.html';
  static const String accountDeletionUrl =
      'https://faysarukattil.github.io/buddy_2.0/delete-account.html';
  static const String homeUrl =
      'https://faysarukattil.github.io/buddy_2.0/';

  static Future<void> openPrivacyPolicy(BuildContext context) async {
    await _launchUrl(context, privacyPolicyUrl, 'Privacy Policy');
  }

  static Future<void> openTerms(BuildContext context) async {
    await _launchUrl(context, termsUrl, 'Terms of Service');
  }

  static Future<void> openAccountDeletionInfo(BuildContext context) async {
    await _launchUrl(context, accountDeletionUrl, 'Account Deletion Guide');
  }

  static Future<void> _launchUrl(
    BuildContext context,
    String urlString,
    String label,
  ) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        AppSnackbar.showError(context, 'Could not open $label');
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.showError(context, 'Error opening $label: $e');
      }
    }
  }
}

