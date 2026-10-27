import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/services/feedback_service.dart';

class SupportService {
  static const String buyMeChaiUrl = 'https://buymeachai.in/faysarukattil';

  static const String keyFirstInstallTime = 'first_app_install_time';
  static const String keyLastSupportPromptTime = 'last_support_prompt_time';

  /// Records the first app install/launch timestamp if not already set.
  static Future<void> recordFirstInstallIfNeeded([SharedPreferences? testPrefs]) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    if (!prefs.containsKey(keyFirstInstallTime)) {
      await prefs.setInt(
        keyFirstInstallTime,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  /// Checks if the user has been using the app for >= 30 days and has not been prompted in the last 30 days.
  static Future<bool> shouldShowSupportPrompt([
    SharedPreferences? testPrefs,
    DateTime? testNow,
  ]) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final now = testNow ?? DateTime.now();

    final firstInstallMs = prefs.getInt(keyFirstInstallTime);
    if (firstInstallMs == null) {
      // Record first install now; user hasn't used app for a month yet
      await prefs.setInt(keyFirstInstallTime, now.millisecondsSinceEpoch);
      return false;
    }

    final firstInstall = DateTime.fromMillisecondsSinceEpoch(firstInstallMs);
    final daysSinceInstall = now.difference(firstInstall).inDays;

    // Must be using app for at least 30 days (1 month)
    if (daysSinceInstall < 30) {
      return false;
    }

    // Check if prompted in the last 30 days
    final lastPromptMs = prefs.getInt(keyLastSupportPromptTime);
    if (lastPromptMs != null) {
      final lastPrompt = DateTime.fromMillisecondsSinceEpoch(lastPromptMs);
      final daysSinceLastPrompt = now.difference(lastPrompt).inDays;
      if (daysSinceLastPrompt < 30) {
        return false;
      }
    }

    return true;
  }

  /// Records that the prompt was shown today.
  static Future<void> markSupportPromptShown([
    SharedPreferences? testPrefs,
    DateTime? testNow,
  ]) async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final now = testNow ?? DateTime.now();
    await prefs.setInt(
      keyLastSupportPromptTime,
      now.millisecondsSinceEpoch,
    );
  }

  /// Launches the Buy Me a Chai link in the device's default browser.
  static Future<void> openBuyMeChai(BuildContext context) async {
    final Uri uri = Uri.parse(buyMeChaiUrl);

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        _copyFallback(context);
      }
    } catch (e) {
      debugPrint('Error launching Buy Me a Chai link: $e');
      if (context.mounted) {
        _copyFallback(context);
      }
    }
  }

  static void _copyFallback(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: buyMeChaiUrl));
    AppSnackbar.showInfo(
      context,
      'Support link copied to clipboard: $buyMeChaiUrl',
      duration: const Duration(seconds: 4),
    );
  }

  /// Checks eligibility and shows the monthly dialog after a brief delay.
  static Future<void> checkAndShowMonthlySupportPrompt(BuildContext context) async {
    await recordFirstInstallIfNeeded();

    final eligible = await shouldShowSupportPrompt();
    if (!eligible) return;

    // Short 2.5s delay so screen is fully rendered and user isn't startled
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!context.mounted) return;

    await markSupportPromptShown();
    if (!context.mounted) return;

    await showSupportPromptDialog(context);
  }

  /// Displays the warm, polite "Buy Me a Chai & Rate the App" popup dialog.
  static Future<void> showSupportPromptDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.cardOf(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: AppColors.borderOf(ctx).withValues(alpha: 0.6),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Chai Cup Icon Container
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFFB74D), // Golden amber
                        Color(0xFFFF7043), // Warm chai peach
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF7043).withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.local_cafe_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Headline
                Text(
                  'Enjoying Buddy? ☕',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimaryOf(ctx),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),

                // Friendly message
                Text(
                  "You've been tracking your expenses with Buddy for over a month! 💛\n\nBuddy is completely free and ad-free. If it has made your financial life easier, consider buying the developer a chai to help keep the app growing!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondaryOf(ctx),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),

                // Primary Button: Buy Me a Chai
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: const Color(0xFFE65100).withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      openBuyMeChai(context);
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_cafe_rounded, size: 19),
                        SizedBox(width: 8),
                        Text(
                          'Buy Me a Chai ☕',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Secondary Button: Rate the App / Feedback
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.borderOf(ctx),
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      FeedbackService.openPlayStore(context);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: Color(0xFFFFB300),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Rate App / Send Feedback',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimaryOf(ctx),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Dismiss: Maybe Later
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Maybe later',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textLightOf(ctx),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
