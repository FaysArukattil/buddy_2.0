import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const String _themePrefKey = 'app_theme_mode';

  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Current theme mode value
  static ThemeMode get currentMode => themeModeNotifier.value;

  /// Initializes the theme from persistent storage.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themePrefKey);

      if (savedTheme == 'light') {
        themeModeNotifier.value = ThemeMode.light;
      } else if (savedTheme == 'dark') {
        themeModeNotifier.value = ThemeMode.dark;
      } else {
        themeModeNotifier.value = ThemeMode.system;
      }
    } catch (e) {
      debugPrint('Error initializing ThemeService: $e');
      themeModeNotifier.value = ThemeMode.system;
    }
  }

  /// Sets the theme mode and persists it to SharedPreferences.
  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      String modeStr = 'system';
      if (mode == ThemeMode.light) {
        modeStr = 'light';
      } else if (mode == ThemeMode.dark) {
        modeStr = 'dark';
      }
      await prefs.setString(_themePrefKey, modeStr);
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  /// Toggles between light and dark mode explicitly.
  static Future<void> toggleTheme(BuildContext context) async {
    final currentIsDark = isDarkMode(context);
    await setThemeMode(currentIsDark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Determines if the current display is in dark mode (resolving system brightness if ThemeMode.system).
  static bool isDarkMode(BuildContext context) {
    if (themeModeNotifier.value == ThemeMode.dark) {
      return true;
    }
    if (themeModeNotifier.value == ThemeMode.light) {
      return false;
    }
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  /// Returns user-friendly name of the current mode.
  static String getModeTitle(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System Default';
    }
  }
}
