import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/services/support_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupportService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Support link is set to buymeachai.in/faysarukattil', () {
      expect(
        SupportService.buyMeChaiUrl,
        'https://buymeachai.in/faysarukattil',
      );
    });

    test('First app launch records install timestamp and returns false', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 10, 11);

      final shouldShow = await SupportService.shouldShowSupportPrompt(prefs, now);
      expect(shouldShow, isFalse);
      expect(prefs.containsKey(SupportService.keyFirstInstallTime), isTrue);
    });

    test('Under 30 days of usage does not trigger monthly prompt', () async {
      final prefs = await SharedPreferences.getInstance();
      final installDate = DateTime(2026, 10, 1);
      final now = DateTime(2026, 10, 15); // 14 days later

      await prefs.setInt(
        SupportService.keyFirstInstallTime,
        installDate.millisecondsSinceEpoch,
      );

      final shouldShow = await SupportService.shouldShowSupportPrompt(prefs, now);
      expect(shouldShow, isFalse);
    });

    test('Over 30 days of usage triggers prompt when not previously shown', () async {
      final prefs = await SharedPreferences.getInstance();
      final installDate = DateTime(2026, 9, 1);
      final now = DateTime(2026, 10, 11); // 40 days later

      await prefs.setInt(
        SupportService.keyFirstInstallTime,
        installDate.millisecondsSinceEpoch,
      );

      final shouldShow = await SupportService.shouldShowSupportPrompt(prefs, now);
      expect(shouldShow, isTrue);
    });

    test('Prompt is suppressed if shown within the last 30 days', () async {
      final prefs = await SharedPreferences.getInstance();
      final installDate = DateTime(2026, 8, 1);
      final lastPrompt = DateTime(2026, 10, 5); // 6 days ago
      final now = DateTime(2026, 10, 11);

      await prefs.setInt(
        SupportService.keyFirstInstallTime,
        installDate.millisecondsSinceEpoch,
      );
      await prefs.setInt(
        SupportService.keyLastSupportPromptTime,
        lastPrompt.millisecondsSinceEpoch,
      );

      final shouldShow = await SupportService.shouldShowSupportPrompt(prefs, now);
      expect(shouldShow, isFalse);
    });

    test('Prompt is re-triggered once a month (>= 30 days since last prompt)', () async {
      final prefs = await SharedPreferences.getInstance();
      final installDate = DateTime(2026, 8, 1);
      final lastPrompt = DateTime(2026, 9, 5); // 36 days ago
      final now = DateTime(2026, 10, 11);

      await prefs.setInt(
        SupportService.keyFirstInstallTime,
        installDate.millisecondsSinceEpoch,
      );
      await prefs.setInt(
        SupportService.keyLastSupportPromptTime,
        lastPrompt.millisecondsSinceEpoch,
      );

      final shouldShow = await SupportService.shouldShowSupportPrompt(prefs, now);
      expect(shouldShow, isTrue);
    });

    test('markSupportPromptShown records current timestamp', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 10, 11, 12, 0);

      await SupportService.markSupportPromptShown(prefs, now);
      expect(
        prefs.getInt(SupportService.keyLastSupportPromptTime),
        now.millisecondsSinceEpoch,
      );
    });
  });
}
