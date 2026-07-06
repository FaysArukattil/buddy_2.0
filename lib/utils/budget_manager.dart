import 'package:shared_preferences/shared_preferences.dart';

class BudgetManager {
  static const String _monthlyBudgetKey = 'monthly_budget';
  static const String _budgetAlertsKey = 'budget_alerts_enabled';
  
  static Future<double> getMonthlyBudget() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_monthlyBudgetKey) ?? 0.0;
  }
  
  static Future<void> setMonthlyBudget(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_monthlyBudgetKey, amount);
  }
  
  static Future<bool> areBudgetAlertsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_budgetAlertsKey) ?? true;
  }
  
  static Future<void> setBudgetAlertsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_budgetAlertsKey, enabled);
  }
  
  static double calculateBudgetPercentage(double spent, double budget) {
    if (budget <= 0) return 0;
    return (spent / budget).clamp(0.0, 1.0);
  }
  
  static String getBudgetStatus(double spent, double budget) {
    if (budget <= 0) return 'No budget set';
    
    final percentage = calculateBudgetPercentage(spent, budget) * 100;
    
    if (percentage >= 100) {
      return 'Budget exceeded!';
    } else if (percentage >= 90) {
      return 'Almost at budget limit';
    } else if (percentage >= 75) {
      return '${percentage.toStringAsFixed(0)}% of budget used';
    } else {
      return 'Within budget';
    }
  }
}
