// lib/services/widget_service.dart
// Native implementation — no home_widget dependency.
// Writes data directly to the shared-preferences file that the Kotlin widget
// providers read, then triggers widget updates via a MethodChannel call into
// the platform side.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/services/preference_service.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/services/currency_service.dart';

class WidgetService {
  static const String appWidgetProviderName = 'BuddyWidgetProvider';
  static const String statsWidgetProviderName = 'BuddyStatsWidgetProvider';

  // MethodChannel used by the native BuddyWidgetChannel.kt to:
  //  1. Save key-value pairs into the SharedPreferences file the widget reads.
  //  2. Trigger AppWidgetManager.updateAppWidget for our two providers.
  static const MethodChannel _channel =
      MethodChannel('com.faysarukattil.buddy/widget');

  /// Updates the home screen widgets with today's transactions and month metrics.
  static Future<void> updateFromTransactions(
      List<TransactionModel> transactions) async {
    try {
      final now = DateTime.now();
      final monthName = DateFormat('MMMM').format(now);

      // 1. Deduplicate transactions once
      final deduped = TransactionModel.deduplicate(transactions);

      // 2. Today page base: strictly exclude Lending & Borrowing
      final todayBase = deduped
          .where((t) => t.category != 'Lending' && t.category != 'Borrowing')
          .toList(growable: false);

      double todayExpense = 0;
      double todayIncome = 0;
      final List<TransactionModel> todayTxns = [];

      for (final txn in todayBase) {
        final isToday = txn.date.year == now.year &&
            txn.date.month == now.month &&
            txn.date.day == now.day;
        if (!isToday) continue;

        final isIncome = txn.type.toLowerCase().trim() == 'income';
        if (isIncome) {
          todayIncome += txn.amount;
        } else {
          todayExpense += txn.amount;
        }
        todayTxns.add(txn);
      }
      todayTxns.sort((a, b) => b.date.compareTo(a.date));

      // 3. Month totals: match HomeScreen._recalculateTotals exactly
      final bool includeDebts = PreferenceService.includeDebtsInHome;
      final monthBase = includeDebts
          ? deduped
          : deduped
              .where(
                  (t) => t.category != 'Lending' && t.category != 'Borrowing')
              .toList(growable: false);

      double monthExpense = 0;
      double monthIncome = 0;
      double lastMonthExpense = 0;
      final lastMonthDate = DateTime(now.year, now.month - 1, 1);

      for (final txn in monthBase) {
        final isIncome = txn.type.toLowerCase().trim() == 'income';
        final isThisMonth =
            txn.date.year == now.year && txn.date.month == now.month;
        final isLastMonth = txn.date.year == lastMonthDate.year &&
            txn.date.month == lastMonthDate.month;

        if (isThisMonth) {
          if (isIncome) {
            monthIncome += txn.amount;
          } else {
            monthExpense += txn.amount;
          }
        } else if (isLastMonth && !isIncome) {
          lastMonthExpense += txn.amount;
        }
      }

      final monthBalance = monthIncome - monthExpense;
      final isNegativeBalance = monthBalance < 0;

      // Delta % vs last month
      final deltaPct = lastMonthExpense > 0
          ? ((monthExpense - lastMonthExpense) / lastMonthExpense * 100)
          : 0.0;
      final deltaSign = deltaPct >= 0 ? '+' : '';
      final deltaStr = lastMonthExpense > 0
          ? '$deltaSign${deltaPct.toStringAsFixed(1)}% vs last mo'
          : 'First month';

      // 4. Compact JSON archive (last 65 days) for Kotlin native canvas rendering
      final cutoff65Days = now.subtract(const Duration(days: 65));
      final List<Map<String, dynamic>> compactTxns = [];
      final Map<String, String> categoryColors = {};

      for (final txn in deduped) {
        if (txn.date.isAfter(cutoff65Days)) {
          final isIncome = txn.type.toLowerCase().trim() == 'income';
          final isDebt =
              txn.category == 'Lending' || txn.category == 'Borrowing';
          final note = txn.cleanNote?.trim() ?? '';
          final title = note.isNotEmpty ? note : txn.category;
          final timeStr = _formatTime(txn.date);
          final subtitle =
              '${txn.category} • ${txn.autoDetected ? 'Auto' : 'Manual'} • $timeStr';
          final amountStr =
              '${isIncome ? '+' : '-'}${FormatUtils.formatCurrency(txn.amount)}';

          final color =
              isIncome ? AppColors.income : AppColors.getCategoryColor(txn.category);
          final colorHex =
              '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';
          categoryColors[txn.category] = colorHex;

          compactTxns.add({
            'year': txn.date.year,
            'month': txn.date.month,
            'day': txn.date.day,
            'amount': txn.amount,
            'is_income': isIncome,
            'is_auto': txn.autoDetected,
            'is_debt': isDebt,
            'title': title,
            'subtitle': subtitle,
            'amount_str': amountStr,
            'category': txn.category,
            'color': colorHex,
          });
        }
      }

      // 5. Assemble the data map
      final dateLabel = DateFormat('EEE, d MMM').format(now);
      final Map<String, Object> data = {
        'today_date_label': dateLabel,
        'today_spent': todayExpense >= 1000000
            ? FormatUtils.formatCompactCurrency(todayExpense)
            : FormatUtils.formatCurrency(todayExpense),
        'today_spent_compact': FormatUtils.formatCompactCurrency(todayExpense),
        'today_spent_raw': todayExpense,
        'today_income': todayIncome >= 1000000
            ? FormatUtils.formatCompactCurrency(todayIncome)
            : FormatUtils.formatCurrency(todayIncome),
        'today_income_formatted': todayIncome >= 1000000
            ? '+${FormatUtils.formatCompactCurrency(todayIncome)}'
            : '+${FormatUtils.formatCurrency(todayIncome)}',
        'today_income_compact': '+${FormatUtils.formatCompactCurrency(todayIncome)}',
        'today_income_raw': todayIncome,
        'today_count': todayTxns.length,

        // Month Page 3-Tile Data
        'month_name': monthName,
        'month_spent': monthExpense >= 1000000
            ? FormatUtils.formatCompactCurrency(monthExpense)
            : FormatUtils.formatCurrency(monthExpense),
        'month_spent_compact': FormatUtils.formatCompactCurrency(monthExpense),
        'month_spent_raw': monthExpense,
        'month_spent_label': '$monthName · Spent',
        'month_income': monthIncome >= 1000000
            ? '+${FormatUtils.formatCompactCurrency(monthIncome)}'
            : '+${FormatUtils.formatCurrency(monthIncome)}',
        'month_income_compact': '+${FormatUtils.formatCompactCurrency(monthIncome)}',
        'month_income_raw': monthIncome,
        'month_earned_label': '$monthName · Earned',
        'month_balance': (isNegativeBalance ? '-' : '') +
            (monthBalance.abs() >= 1000000
                ? FormatUtils.formatCompactCurrency(monthBalance.abs())
                : FormatUtils.formatCurrency(monthBalance.abs())),
        'month_balance_compact': (isNegativeBalance ? '-' : '') +
            FormatUtils.formatCompactCurrency(monthBalance.abs()),
        'month_balance_raw': monthBalance,
        'month_balance_label':
            isNegativeBalance ? '$monthName · Deficit' : '$monthName · Balance',
        'month_is_negative': isNegativeBalance,
        'month_delta': deltaStr,
        'month_ratio': (monthIncome > 0)
            ? (monthExpense / monthIncome).clamp(0.0, 2.0)
            : 1.0,

        // Preferences & Raw Data for Kotlin Native Canvas Rendering
        'include_debts_in_home': includeDebts,
        'recent_txns_json': jsonEncode(compactTxns),
        'category_colors_json': jsonEncode(categoryColors),
        // Currency — read by BuddyWidgetProvider for dynamic symbol display
        'currency_symbol': CurrencyService.currencySymbol,
        'currency_code': CurrencyService.currencyCode,
      };

      // Populate up to 8 today's transactions for the responsive list
      for (int i = 0; i < 8; i++) {
        if (i < todayTxns.length) {
          final t = todayTxns[i];
          final isInc = t.type.toLowerCase().trim() == 'income';
          final note = t.cleanNote?.trim() ?? '';
          final title = note.isNotEmpty ? note : t.category;
          final timeStr = _formatTime(t.date);
          final subtitle = '${t.category} • $timeStr';
          final amountStr =
              '${isInc ? '+' : '-'}${FormatUtils.formatCurrency(t.amount)}';

          final color =
              isInc ? AppColors.income : AppColors.getCategoryColor(t.category);
          final colorHex =
              '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

          data['txn_${i}_exists'] = true;
          data['txn_${i}_title'] = title;
          data['txn_${i}_subtitle'] = subtitle;
          data['txn_${i}_amount'] = amountStr;
          data['txn_${i}_category'] = t.category;
          data['txn_${i}_color'] = colorHex;
          data['txn_${i}_is_income'] = isInc;
          data['txn_${i}_is_auto'] = t.autoDetected;
        } else {
          data['txn_${i}_exists'] = false;
        }
      }

      // 6. Push data & trigger update via native channel
      await _channel.invokeMethod('updateWidget', data);

      debugPrint(
          '📱 WIDGET: Pushed Today & Month data (${todayTxns.length} txns today, $monthName)');
    } catch (e, stack) {
      debugPrint('⚠️ WIDGET: Error updating widget: $e\n$stack');
    }
  }

  static String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h12:$minute $period';
  }
}
