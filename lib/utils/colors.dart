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

  static Color textMutedOf(BuildContext context) =>
      isDark(context) ? darkTextLight : textLight;

  // ── Distinct Category Color Palette (Zero duplicates across all categories) ──
  static const Map<String, Color> categoryColors = {
    // Expense categories
    'Food & Dining': Color(0xFFFF7A45),     // Coral Orange
    'Groceries': Color(0xFF43A047),         // Medium Green
    'Grocery': Color(0xFF2E7D32),           // Dark Forest Green
    'Swiggy': Color(0xFFFC8019),            // Brand Orange
    'Zomato': Color(0xFFCB202D),            // Brand Crimson Red
    'Zepto': Color(0xFF6B21A8),             // Electric Violet
    'Instamart': Color(0xFFFF9100),         // Amber Orange
    'Amazon': Color(0xFFFF9900),            // Amazon Deep Gold
    'Flipkart': Color(0xFF2874F0),          // Flipkart Royal Blue
    'Myntra': Color(0xFFFF3F6C),            // Brand Magenta
    'Transport': Color(0xFF3F51B5),         // Deep Indigo
    'Uber': Color(0xFF455A64),              // Charcoal Slate
    'Ola': Color(0xFF7CB342),               // Light Olive Green
    'Rapido': Color(0xFFFFD600),            // Bright Yellow
    'Fuel': Color(0xFFE65100),              // Deep Rust Orange
    'Netflix': Color(0xFFE50914),           // Pure Netflix Red
    'YouTube': Color(0xFFFF0000),           // Vivid Bright Red
    'Spotify': Color(0xFF1DB954),           // Spotify Mint
    'Hotstar': Color(0xFF0038A8),           // Deep Hotstar Navy
    'Gym & Fitness': Color(0xFF00897B),      // Deep Mint Teal
    'Medical': Color(0xFF00BCD4),           // Cyan
    'Education': Color(0xFF5E35B1),         // Deep Violet
    'Rent': Color(0xFF795548),              // Warm Espresso
    'Bills & Utilities': Color(0xFF009688), // Sea Green / Teal
    'Recharge': Color(0xFF0288D1),          // Cerulean Blue
    'Coffee': Color(0xFF4E342E),            // Dark Coffee Brown
    'Travel': Color(0xFF1E88E5),            // Azure Blue
    'Party': Color(0xFFAB47BC),             // Lavender Purple
    'Gifts & Charity': Color(0xFFF06292),   // Rose Pink
    'Subscriptions': Color(0xFF607D8B),     // Slate Steel
    'Clothing': Color(0xFFD81B60),          // Rich Ruby Pink
    'Pets': Color(0xFFFF8F00),              // Warm Amber
    'Local Food': Color(0xFFFF6E40),        // Deep Peach
    'Jio Internet': Color(0xFF0A2885),      // Jio Midnight Blue
    'WiFi': Color(0xFF0097A7),              // Ocean Cyan
    'Lending': Color(0xFF10B981),           // Bright Emerald
    'Other': Color(0xFF78909C),             // Cool Silver Slate
    // Income categories
    'Salary': Color(0xFF16A34A),            // Rich Grass Green
    'Freelance': Color(0xFF8B5CF6),         // Purple Iris
    'Business': Color(0xFF0284C7),          // Corporate Sky
    'Investment': Color(0xFF059669),        // Mountain Green
    'Interest': Color(0xFFD97706),          // Honey Topaz
    'Refund': Color(0xFF0D9488),            // Dark Aquamarine
    'Gift': Color(0xFFEC4899),              // Bubblegum Pink
    'Cashback': Color(0xFF14B8A6),          // Caribbean Aqua
    'Rental Income': Color(0xFF92400E),     // Burnished Bronze
    'Borrowing': Color(0xFFEA580C),         // Burnt Sienna
  };

  /// Curated palette for creating custom categories with distinct colors
  static const List<Color> curatedCategoryColors = [
    Color(0xFFFF7A45), // Coral
    Color(0xFFFC8019), // Orange
    Color(0xFFFFD600), // Yellow
    Color(0xFF10B981), // Emerald
    Color(0xFF059669), // Green
    Color(0xFF00BCD4), // Cyan
    Color(0xFF0284C7), // Sky Blue
    Color(0xFF3F51B5), // Indigo
    Color(0xFF8B5CF6), // Purple
    Color(0xFFAB47BC), // Lavender
    Color(0xFFEC4899), // Pink
    Color(0xFFE11D48), // Rose Red
    Color(0xFFCB202D), // Crimson
    Color(0xFF92400E), // Bronze
    Color(0xFF795548), // Brown
    Color(0xFF4E342E), // Dark Mocha
    Color(0xFF607D8B), // Slate
    Color(0xFF00897B), // Deep Teal
    Color(0xFF7CB342), // Olive Lime
    Color(0xFFD97706), // Amber
  ];

  /// In-memory cache for custom category colors created by user
  static final Map<String, Color> _customColors = {};

  /// Register custom category color
  static void registerCategoryColor(String name, Color color) {
    _customColors[name] = color;
  }

  /// Get color for a category name, with fallback to registered or deterministic color
  static Color getCategoryColor(String categoryName) {
    if (_customColors.containsKey(categoryName)) {
      return _customColors[categoryName]!;
    }
    if (categoryColors.containsKey(categoryName)) {
      return categoryColors[categoryName]!;
    }
    // Deterministic selection from curated palette so any user category has a distinct vibrant color
    final hash = categoryName.hashCode.abs();
    return curatedCategoryColors[hash % curatedCategoryColors.length];
  }

  /// Get a lighter tint of the category color for backgrounds
  static Color getCategoryBgColor(String categoryName, [BuildContext? context]) {
    final color = getCategoryColor(categoryName);
    if (context != null && isDark(context)) {
      return color.withValues(alpha: 0.18);
    }
    return color.withValues(alpha: 0.12);
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
