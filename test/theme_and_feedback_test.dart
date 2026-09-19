import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/services/theme_service.dart';
import 'package:buddy/services/feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('ThemeService initializes with system mode by default', () async {
      await ThemeService.initialize();
      expect(ThemeService.currentMode, ThemeMode.system);
      expect(ThemeService.themeModeNotifier.value, ThemeMode.system);
    });

    test('ThemeService updates mode and notifies listeners', () async {
      await ThemeService.initialize();

      ThemeMode? observed;
      ThemeService.themeModeNotifier.addListener(() {
        observed = ThemeService.themeModeNotifier.value;
      });

      await ThemeService.setThemeMode(ThemeMode.dark);
      expect(ThemeService.currentMode, ThemeMode.dark);
      expect(observed, ThemeMode.dark);

      await ThemeService.setThemeMode(ThemeMode.light);
      expect(ThemeService.currentMode, ThemeMode.light);
      expect(observed, ThemeMode.light);
    });

    test('ThemeService restores persisted preference', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'dark'});
      await ThemeService.initialize();
      expect(ThemeService.currentMode, ThemeMode.dark);
    });
  });

  group('FeedbackService Tests', () {
    test('Developer recipient email is faysarukattil@gmail.com', () {
      expect(FeedbackService.developerEmail, 'faysarukattil@gmail.com');
    });

    test('createMailUri constructs valid mailto URI', () {
      final uri = FeedbackService.createMailUri(
        subject: '[Bug Report] Test issue',
        body: 'Here are the details',
      );

      expect(uri.scheme, 'mailto');
      expect(uri.path, 'faysarukattil@gmail.com');
      expect(uri.queryParameters['subject'], '[Bug Report] Test issue');
      expect(uri.queryParameters['body'], 'Here are the details');
    });
  });
}
