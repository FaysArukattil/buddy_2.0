import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF69AEA9);
  static const Color secondary = Color(0xFF3F8782);

  // Background Colors
  static const Color background = Color(0xFFF5F5F5);
  static const Color cardBackground = Colors.white;
  static const Color darkBackground = Color(0xFF1E1E1E);

  // Text Colors
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color textLight = Color(0xFFB2BEC3);
  static const Color textWhite = Colors.white;

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

  // ── Category Color Palette ──
  // Curated pastel/vibrant colors for category icons
  static const Map<String, Color> categoryColors = {
    // Expense categories
    'Food & Dining': Color(0xFFFF8A65),
    'Groceries': Color(0xFF66BB6A),
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
  static Color getCategoryBgColor(String categoryName) {
    final color = getCategoryColor(categoryName);
    return Color.fromARGB(30, color.red, color.green, color.blue);
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
}
