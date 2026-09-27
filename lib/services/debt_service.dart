// lib/services/debt_service.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/debt.dart';
import '../models/transaction.dart';
import 'firestore_service.dart';
import 'notification_helper.dart';

class DebtService {
  static final DebtService instance = DebtService._();
  DebtService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _debtCol {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');
    return _db.collection('users').doc(uid).collection('debts');
  }

  /// Add a new Borrow or Lend record
  /// Automatically creates an Expense (if Lend) or Income (if Borrow) transaction
  Future<String> addDebt(DebtModel debt) async {
    final now = DateTime.now();
    final dateWithTime = DateTime(
      debt.date.year,
      debt.date.month,
      debt.date.day,
      now.hour,
      now.minute,
      now.second,
    );

    // 1. Create linked transaction
    String? linkedTxnId;
    try {
      final isLend = debt.isLend;
      final txnType = isLend ? 'expense' : 'income';
      final category = isLend ? 'Lending' : 'Borrowing';
      final iconCodePoint = isLend
          ? Icons.arrow_outward_rounded.codePoint
          : Icons.arrow_downward_rounded.codePoint;

      final formattedDueDate = DateFormat('dd MMM yyyy').format(debt.dueDate);
      final notePrefix = isLend
          ? 'Lent to ${debt.personName}'
          : 'Borrowed from ${debt.personName}';
      final extraNote = debt.note != null && debt.note!.trim().isNotEmpty
          ? ' (${debt.note!.trim()})'
          : '';
      final dueInfo = isLend
          ? ' • Due: $formattedDueDate'
          : ' • Repay by: $formattedDueDate';

      final txn = TransactionModel(
        amount: debt.amount,
        type: txnType,
        date: dateWithTime,
        category: category,
        icon: iconCodePoint,
        note: '$notePrefix$extraNote$dueInfo',
      );

      linkedTxnId = await FirestoreService.instance.addTransaction(txn);
      debugPrint('✅ DEBT: Created linked $txnType transaction: $linkedTxnId');
    } catch (e) {
      debugPrint('⚠️ DEBT: Failed to create linked transaction: $e');
    }

    // 2. Schedule notification if requested
    final notificationId =
        (debt.dueDate.millisecondsSinceEpoch ~/ 1000 + debt.personName.hashCode)
                .abs() %
            100000;

    if (debt.remindOnDueDate) {
      try {
        await NotificationHelper.scheduleRepaymentReminder(
          id: notificationId,
          personName: debt.personName,
          amount: debt.amount,
          type: debt.type,
          dueDate: debt.dueDate,
        );
      } catch (e) {
        debugPrint('⚠️ DEBT: Failed to schedule reminder: $e');
      }
    }

    // 3. Save debt to Firestore
    final debtWithMeta = debt.copyWith(
      transactionId: linkedTxnId,
      notificationId: notificationId,
      createdAt: now,
    );

    final docRef = await _debtCol.add(debtWithMeta.toFirestore());
    debugPrint('✅ DEBT: Saved debt record with ID: ${docRef.id}');
    return docRef.id;
  }

  /// Update an existing debt record
  Future<void> updateDebt(DebtModel debt) async {
    if (debt.id == null) return;

    // Update linked transaction if it exists
    if (debt.transactionId != null) {
      try {
        final isLend = debt.isLend;
        final formattedDueDate = DateFormat('dd MMM yyyy').format(debt.dueDate);
        final notePrefix = isLend
            ? 'Lent to ${debt.personName}'
            : 'Borrowed from ${debt.personName}';
        final extraNote = debt.note != null && debt.note!.trim().isNotEmpty
            ? ' (${debt.note!.trim()})'
            : '';
        final dueInfo = isLend
            ? ' • Due: $formattedDueDate'
            : ' • Repay by: $formattedDueDate';

        await FirestoreService.instance.updateTransaction(
          debt.transactionId!,
          {
            'amount': debt.amount,
            'note': '$notePrefix$extraNote$dueInfo',
            'date': debt.date,
          },
        );
      } catch (e) {
        debugPrint('⚠️ DEBT: Failed to update linked transaction: $e');
      }
    }

    // Reschedule reminder if needed
    if (debt.notificationId != null) {
      await NotificationHelper.cancelNotification(debt.notificationId!);
      if (debt.remindOnDueDate && !debt.isRepaid) {
        await NotificationHelper.scheduleRepaymentReminder(
          id: debt.notificationId!,
          personName: debt.personName,
          amount: debt.amount,
          type: debt.type,
          dueDate: debt.dueDate,
        );
      }
    }

    await _debtCol.doc(debt.id).update(debt.toFirestore());
    debugPrint('✅ DEBT: Updated debt record ${debt.id}');
  }

  /// Mark a debt as repaid or pending
  Future<void> markAsRepaid({
    required DebtModel debt,
    required bool isRepaid,
    bool recordTransaction = false,
  }) async {
    if (debt.id == null) return;

    String? repaymentTxnId = debt.repaymentTransactionId;

    if (isRepaid) {
      // Cancel reminder notification when settled
      if (debt.notificationId != null) {
        await NotificationHelper.cancelNotification(debt.notificationId!);
      }

      // Record repayment transaction if chosen
      if (recordTransaction) {
        try {
          final isLend = debt.isLend;
          // If I lent money and they repaid me -> Income
          // If I borrowed money and I repaid them -> Expense
          final txnType = isLend ? 'income' : 'expense';
          final category = isLend ? 'Lending' : 'Borrowing';
          final note = isLend
              ? 'Repayment received from ${debt.personName}${debt.note != null && debt.note!.isNotEmpty ? " (${debt.note})" : ""}'
              : 'Repaid borrowed money to ${debt.personName}${debt.note != null && debt.note!.isNotEmpty ? " (${debt.note})" : ""}';

          final txn = TransactionModel(
            amount: debt.amount,
            type: txnType,
            date: DateTime.now(),
            category: category,
            icon: isLend
                ? Icons.arrow_downward_rounded.codePoint
                : Icons.arrow_outward_rounded.codePoint,
            note: note,
          );

          repaymentTxnId =
              await FirestoreService.instance.addTransaction(txn);
          debugPrint('✅ DEBT: Recorded repayment transaction $repaymentTxnId');
        } catch (e) {
          debugPrint('⚠️ DEBT: Failed to record repayment transaction: $e');
        }
      }
    } else {
      // Reopening debt - delete repayment transaction if one was recorded
      if (repaymentTxnId != null) {
        try {
          await FirestoreService.instance.deleteTransaction(repaymentTxnId);
          repaymentTxnId = null;
        } catch (e) {
          debugPrint('⚠️ DEBT: Failed to remove repayment transaction: $e');
        }
      }
      // Re-enable reminder if due date is still in future
      if (debt.remindOnDueDate && debt.notificationId != null) {
        await NotificationHelper.scheduleRepaymentReminder(
          id: debt.notificationId!,
          personName: debt.personName,
          amount: debt.amount,
          type: debt.type,
          dueDate: debt.dueDate,
        );
      }
    }

    await _debtCol.doc(debt.id).update({
      'isRepaid': isRepaid,
      'repaidDate': isRepaid ? Timestamp.fromDate(DateTime.now()) : null,
      'repaymentTransactionId': repaymentTxnId,
    });

    debugPrint('✅ DEBT: Marked debt ${debt.id} as isRepaid=$isRepaid');
  }

  /// Partially settle a debt.
  /// [settledAmount] is how much was paid now.
  /// Records the settled portion as a transaction.
  /// If settledAmount >= debt.amount, marks as fully repaid.
  /// Otherwise, reduces the debt amount to the remainder.
  Future<void> partialSettle({
    required DebtModel debt,
    required double settledAmount,
    bool recordTransaction = true,
  }) async {
    if (debt.id == null) return;
    final settledAmount_ = settledAmount.clamp(0.0, debt.amount);
    final remaining = debt.amount - settledAmount_;
    final isFullySettled = remaining <= 0.001;

    // 1. Record a transaction for the settled portion
    if (recordTransaction && settledAmount_ > 0) {
      try {
        final isLend = debt.isLend;
        // Lend repaid -> income for me; Borrow repaid -> expense for me
        final txnType = isLend ? 'income' : 'expense';
        final category = isLend ? 'Lending' : 'Borrowing';
        final partialNote = isFullySettled ? 'Full' : 'Partial';
        final note = isLend
            ? '$partialNote repayment from ${debt.personName}'
            : '$partialNote repayment to ${debt.personName}';

        final txn = TransactionModel(
          amount: settledAmount_,
          type: txnType,
          date: DateTime.now(),
          category: category,
          icon: isLend
              ? Icons.arrow_downward_rounded.codePoint
              : Icons.arrow_outward_rounded.codePoint,
          note: note,
        );
        final txnId = await FirestoreService.instance.addTransaction(txn);
        debugPrint('✅ DEBT: Recorded partial settlement txn $txnId');
      } catch (e) {
        debugPrint('⚠️ DEBT: Failed to record partial settlement txn: $e');
      }
    }

    // 2. Cancel reminder if fully settled
    if (isFullySettled && debt.notificationId != null) {
      await NotificationHelper.cancelNotification(debt.notificationId!);
    }

    // 3. Update the debt document
    if (isFullySettled) {
      await _debtCol.doc(debt.id).update({
        'amount': 0.0,
        'isRepaid': true,
        'repaidDate': Timestamp.fromDate(DateTime.now()),
      });
    } else {
      await _debtCol.doc(debt.id).update({
        'amount': remaining,
      });
    }

    debugPrint(
      '✅ DEBT: Partial settle done. Settled ₹$settledAmount_, remaining ₹$remaining, fullySettled=$isFullySettled',
    );
  }

  /// Delete a debt record and optionally its linked transactions
  Future<void> deleteDebt(
    DebtModel debt, {
    bool deleteLinkedTransactions = true,
  }) async {
    if (debt.id == null) return;

    if (debt.notificationId != null) {
      await NotificationHelper.cancelNotification(debt.notificationId!);
    }

    if (deleteLinkedTransactions) {
      if (debt.transactionId != null) {
        try {
          await FirestoreService.instance.deleteTransaction(debt.transactionId!);
          debugPrint('🗑️ DEBT: Deleted initial linked transaction ${debt.transactionId}');
        } catch (e) {
          debugPrint('⚠️ DEBT: Failed to delete initial transaction: $e');
        }
      }
      if (debt.repaymentTransactionId != null) {
        try {
          await FirestoreService.instance
              .deleteTransaction(debt.repaymentTransactionId!);
          debugPrint('🗑️ DEBT: Deleted repayment transaction ${debt.repaymentTransactionId}');
        } catch (e) {
          debugPrint('⚠️ DEBT: Failed to delete repayment transaction: $e');
        }
      }
    }

    await _debtCol.doc(debt.id).delete();
    debugPrint('🗑️ DEBT: Deleted debt doc ${debt.id}');
  }

  /// Real-time stream of all debts
  Stream<List<DebtModel>> getDebtsStream() {
    return _debtCol.orderBy('dueDate', descending: false).snapshots().map(
          (snapshot) =>
              snapshot.docs.map((doc) => DebtModel.fromFirestore(doc)).toList(),
        );
  }

  /// Get list of debts (one-time fetch)
  Future<List<DebtModel>> getAllDebts() async {
    final snapshot =
        await _debtCol.orderBy('dueDate', descending: false).get();
    return snapshot.docs.map((doc) => DebtModel.fromFirestore(doc)).toList();
  }

  /// Get distinct contact names from previous debts for autocomplete
  Future<List<String>> getRecentContacts() async {
    try {
      final debts = await getAllDebts();
      final names = <String>{};
      for (final d in debts) {
        if (d.personName.trim().isNotEmpty) {
          names.add(d.personName.trim());
        }
      }
      return names.toList();
    } catch (_) {
      return [];
    }
  }
}
