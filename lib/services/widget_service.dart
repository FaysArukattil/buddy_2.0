// lib/services/widget_service.dart
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';

class WidgetService {
  static const String appWidgetProviderName = 'BuddyWidgetProvider';

  /// Updates the home screen widget with today's transactions and metrics only
  static Future<void> updateFromTransactions(
      List<TransactionModel> transactions) async {
    try {
      final now = DateTime.now();

      double todayExpense = 0;
      double todayIncome = 0;
      int todayCount = 0;
      int todayAutoCount = 0;
      int todayManualCount = 0;
      double todayAutoExpense = 0;
      double todayManualExpense = 0;

      final visible = TransactionModel.deduplicate(transactions)
          .where((t) => t.category != 'Lending' && t.category != 'Borrowing')
          .toList(growable: false);

      final List<TransactionModel> todayTxns = [];

      for (final txn in visible) {
        final isToday = txn.date.year == now.year &&
            txn.date.month == now.month &&
            txn.date.day == now.day;
        if (!isToday) continue;

        final isIncome = txn.type.toLowerCase().trim() == 'income';
        todayCount++;

        if (isIncome) {
          todayIncome += txn.amount;
        } else {
          todayExpense += txn.amount;
          if (txn.autoDetected) {
            todayAutoExpense += txn.amount;
            todayAutoCount++;
          } else {
            todayManualExpense += txn.amount;
            todayManualCount++;
          }
        }

        todayTxns.add(txn);
      }

      // Sort newest first
      todayTxns.sort((a, b) => b.date.compareTo(a.date));

      final dateLabel = DateFormat('EEE, d MMM').format(now);

      final Map<String, Object> data = {
        'today_date_label': dateLabel,
        'today_spent': FormatUtils.formatCurrency(todayExpense),
        'today_income': FormatUtils.formatCurrency(todayIncome),
        'today_income_formatted': '+${FormatUtils.formatCurrency(todayIncome)}',
        'today_count': todayCount,
        'today_count_label': '$todayCount transaction${todayCount == 1 ? '' : 's'}',
        'today_auto_count': todayAutoCount,
        'today_manual_count': todayManualCount,
        'today_auto_pill':
            '⚡ $todayAutoCount auto · ${FormatUtils.formatCurrency(todayAutoExpense)}',
        'today_manual_pill':
            '✍️ $todayManualCount manual · ${FormatUtils.formatCurrency(todayManualExpense)}',
        'today_split_summary':
            '⚡ $todayAutoCount auto · ✍️ $todayManualCount manual',
        'has_txns': todayTxns.isNotEmpty,
      };

      // Populate up to 4 today's transactions
      for (int i = 0; i < 4; i++) {
        if (i < todayTxns.length) {
          final t = todayTxns[i];
          final isInc = t.type.toLowerCase().trim() == 'income';
          final note = t.cleanNote?.trim() ?? '';
          final title = note.isNotEmpty ? note : t.category;
          final timeStr = _formatTime(t.date);
          final autoBadge = t.autoDetected ? 'Auto' : 'Manual';
          final subtitle = '${t.category} • $autoBadge • $timeStr';
          final amountStr =
              '${isInc ? '+' : '-'}${FormatUtils.formatCurrency(t.amount)}';

          final color = isInc
              ? AppColors.income
              : AppColors.getCategoryColor(t.category);
          final colorHex =
              '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

          data['txn_${i}_exists'] = true;
          data['txn_${i}_title'] = title;
          data['txn_${i}_category'] = t.category;
          data['txn_${i}_subtitle'] = subtitle;
          data['txn_${i}_amount'] = amountStr;
          data['txn_${i}_color'] = colorHex;
          data['txn_${i}_is_income'] = isInc;
          data['txn_${i}_is_auto'] = t.autoDetected;
        } else {
          data['txn_${i}_exists'] = false;
        }
      }

      await Future.wait(
        data.entries.map((e) => HomeWidget.saveWidgetData<Object>(e.key, e.value)),
      );

      await HomeWidget.updateWidget(
        name: appWidgetProviderName,
        androidName: appWidgetProviderName,
      );

      debugPrint('📱 WIDGET: Updated TODAY data (${todayTxns.length} txns today)');
    } catch (e) {
      debugPrint('⚠️ WIDGET: Error updating widget: $e');
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
