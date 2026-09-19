import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF69AEA9);
  static const Color secondary = Color(0xFF3F8782);

  // Light Mode Colors
  static const Color background = Color(0xFFF5F7FA);
  static const Color cardBackground = Colors.white;

  // Dark Mode Colors
  static const Color darkBackground = Color(0xFF12161A);
  static const Color darkCard = Color(0xFF1A2129);
  static const Color darkSurface = Color(0xFF222C36);
  static const Color darkBorder = Color(0xFF2D3945);

  // Light Mode Text Colors
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color textLight = Color(0xFFB2BEC3);
  static const Color textWhite = Colors.white;

  // Dark Mode Text Colors
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextLight = Color(0xFF64748B);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFC107);
  static const Color info = Color(0xFF2196F3);

  // Transaction Colors
  static const Color income = Color(0xFF4CAF50);
  static const Color expense = Color(0xFFFF5252);

  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF69AEA9), Color(0xFF3F8782)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xFF1E2630), Color(0xFF151C23)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dynamic Context Helpers
  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color backgroundOf(BuildContext context) =>
      isDark(context) ? darkBackground : background;

  static Color cardOf(BuildContext context) =>
      isDark(context) ? darkCard : cardBackground;

  static Color surfaceOf(BuildContext context) =>
      isDark(context) ? darkSurface : Colors.white;

  static Color borderOf(BuildContext context) =>
      isDark(context) ? darkBorder : const Color(0xFFE2E8F0);

  static Color textPrimaryOf(BuildContext context) =>
      isDark(context) ? darkTextPrimary : textPrimary;

  static Color textSecondaryOf(BuildContext context) =>
      isDark(context) ? darkTextSecondary : textSecondary;

  static Color textLightOf(BuildContext context) =>
      isDark(context) ? darkTextLight : textLight;

  // ── Category Color Palette ──
  static const Map<String, Color> categoryColors = {
    // Expense categories
    'Food & Dining': Color(0xFFFF8A65),
    'Groceries': Color(0xFF66BB6A),
    'Grocery': Color(0xFF4CAF50),
    'Swiggy': Color(0xFFFF6D00),
    'Zomato': Color(0xFFE23744),
    'Zepto': Color(0xFF7C4DFF),
    'Instamart': Color(0xFFFF9100),
    'Amazon': Color(0xFFFF9800),
    'Flipkart': Color(0xFF2962FF),
    'Myntra': Color(0xFFE91E63),
    'Transport': Color(0xFF5C6BC0),
    'Uber': Color(0xFF263238),
    'Ola': Color(0xFF43A047),
    'Rapido': Color(0xFFFDD835),
    'Fuel': Color(0xFFFFA726),
    'Netflix': Color(0xFFE50914),
    'YouTube': Color(0xFFFF0000),
    'Spotify': Color(0xFF1DB954),
    'Hotstar': Color(0xFF1976D2),
    'Gym & Fitness': Color(0xFF26A69A),
    'Medical': Color(0xFF42A5F5),
    'Education': Color(0xFF5C6BC0),
    'Rent': Color(0xFF8D6E63),
    'Bills & Utilities': Color(0xFF26A69A),
    'Recharge': Color(0xFF29B6F6),
    'Coffee': Color(0xFF795548),
    'Travel': Color(0xFF42A5F5),
    'Party': Color(0xFFAB47BC),
    'Gifts & Charity': Color(0xFFEC407A),
    'Subscriptions': Color(0xFF78909C),
    'Clothing': Color(0xFFE91E63),
    'Pets': Color(0xFFFF7043),
    'Local Food': Color(0xFFFF9E80),
    'Jio Internet': Color(0xFF005AE0),
    'WiFi': Color(0xFF00ACC1),
    'Other': Color(0xFF90A4AE),
    // Income categories
    'Salary': Color(0xFF4CAF50),
    'Freelance': Color(0xFF7E57C2),
    'Business': Color(0xFF1565C0),
    'Investment': Color(0xFF2E7D32),
    'Interest': Color(0xFFFFB300),
    'Refund': Color(0xFF26A69A),
    'Gift': Color(0xFFEC407A),
    'Cashback': Color(0xFF00BFA5),
    'Rental Income': Color(0xFF8D6E63),
  };

  /// Get color for a category name, with fallback
  static Color getCategoryColor(String categoryName) {
    return categoryColors[categoryName] ?? const Color(0xFF90A4AE);
  }

  /// Get a lighter tint of the category color for backgrounds
  static Color getCategoryBgColor(String categoryName, [BuildContext? context]) {
    final color = getCategoryColor(categoryName);
    if (context != null && isDark(context)) {
      return color.withAlpha(45);
    }
    return color.withAlpha(30);
  }

  // Shadow presets
  static List<BoxShadow> get cardShadow => [
        const BoxShadow(
          color: Color(0x14000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get elevatedShadow => [
        const BoxShadow(
          color: Color(0x22000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ];

  static List<BoxShadow> cardShadowOf(BuildContext context) => isDark(context)
      ? [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ]
      : cardShadow;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.cardBackground,
        error: AppColors.error,
      ),
      cardColor: AppColors.cardBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
      ),
      useMaterial3: true,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.darkCard,
        error: AppColors.error,
      ),
      cardColor: AppColors.darkCard,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.darkTextPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.darkTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkCard,
        modalBackgroundColor: AppColors.darkCard,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.darkCard,
      ),
      useMaterial3: true,
    );
  }
}
