// test/debt_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:buddy/models/debt.dart';

void main() {
  group('DebtModel tests', () {
    test('Correctly identifies lend vs borrow', () {
      final lendDebt = DebtModel(
        type: 'lend',
        personName: 'Rahul',
        amount: 1500.0,
        date: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 5)),
      );

      final borrowDebt = DebtModel(
        type: 'borrow',
        personName: 'Priya',
        amount: 800.0,
        date: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 3)),
      );

      expect(lendDebt.isLend, isTrue);
      expect(lendDebt.isBorrow, isFalse);
      expect(borrowDebt.isBorrow, isTrue);
      expect(borrowDebt.isLend, isFalse);
    });

    test('Correctly computes isDueToday, isOverdue, daysDifference', () {
      final now = DateTime.now();

      final todayDebt = DebtModel(
        type: 'lend',
        personName: 'Sam',
        amount: 500,
        date: now.subtract(const Duration(days: 7)),
        dueDate: DateTime(now.year, now.month, now.day),
      );

      final overdueDebt = DebtModel(
        type: 'borrow',
        personName: 'Alex',
        amount: 300,
        date: now.subtract(const Duration(days: 10)),
        dueDate: now.subtract(const Duration(days: 2)),
      );

      final futureDebt = DebtModel(
        type: 'lend',
        personName: 'John',
        amount: 1000,
        date: now,
        dueDate: now.add(const Duration(days: 4)),
      );

      expect(todayDebt.isDueToday, isTrue);
      expect(todayDebt.isOverdue, isFalse);
      expect(todayDebt.daysDifference, 0);

      expect(overdueDebt.isOverdue, isTrue);
      expect(overdueDebt.isDueToday, isFalse);
      expect(overdueDebt.daysDifference, lessThan(0));

      expect(futureDebt.isOverdue, isFalse);
      expect(futureDebt.isDueToday, isFalse);
      expect(futureDebt.daysDifference, greaterThanOrEqualTo(3));
    });

    test('toMap and fromMap serialization', () {
      final original = DebtModel(
        id: 'test_id_123',
        type: 'lend',
        personName: 'Rahul',
        amount: 2500.0,
        date: DateTime(2026, 9, 25),
        dueDate: DateTime(2026, 10, 5),
        note: 'Concert tickets',
        remindOnDueDate: true,
      );

      final map = original.toMap();
      final reconstructed = DebtModel.fromMap(map);

      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.type, equals(original.type));
      expect(reconstructed.personName, equals(original.personName));
      expect(reconstructed.amount, equals(original.amount));
      expect(reconstructed.note, equals(original.note));
      expect(reconstructed.remindOnDueDate, equals(original.remindOnDueDate));
    });

    test('Correctly tracks settlements, totalPaid, and progressPercent', () {
      final debt = DebtModel(
        id: 'debt_settle_1',
        type: 'lend',
        personName: 'Sam',
        amount: 600.0,
        originalAmount: 1000.0,
        date: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 15),
        settlements: [
          DebtSettlement(
            amount: 400.0,
            date: DateTime(2026, 9, 10),
            note: 'First installment',
          ),
        ],
      );

      expect(debt.hasPartialSettlements, isTrue);
      expect(debt.totalPaid, equals(400.0));
      expect(debt.progressPercent, equals(0.4));
      expect(debt.settlements.length, equals(1));
      expect(debt.settlements.first.amount, equals(400.0));
      expect(debt.settlements.first.note, equals('First installment'));
    });

    test('Correctly determines isRepaidOnTime and isRepaidLate', () {
      final dueDate = DateTime(2026, 9, 15);

      final onTimeDebt = DebtModel(
        type: 'lend',
        personName: 'Alice',
        amount: 0.0,
        originalAmount: 500.0,
        date: DateTime(2026, 9, 1),
        dueDate: dueDate,
        isRepaid: true,
        repaidDate: DateTime(2026, 9, 14), // before due date
      );

      final sameDayDebt = DebtModel(
        type: 'lend',
        personName: 'Bob',
        amount: 0.0,
        originalAmount: 500.0,
        date: DateTime(2026, 9, 1),
        dueDate: dueDate,
        isRepaid: true,
        repaidDate: DateTime(2026, 9, 15, 20, 0), // same day
      );

      final lateDebt = DebtModel(
        type: 'lend',
        personName: 'Charlie',
        amount: 0.0,
        originalAmount: 500.0,
        date: DateTime(2026, 9, 1),
        dueDate: dueDate,
        isRepaid: true,
        repaidDate: DateTime(2026, 9, 18), // 3 days late
      );

      expect(onTimeDebt.isRepaidOnTime, isTrue);
      expect(onTimeDebt.isRepaidLate, isFalse);

      expect(sameDayDebt.isRepaidOnTime, isTrue);
      expect(sameDayDebt.isRepaidLate, isFalse);

      expect(lateDebt.isRepaidOnTime, isFalse);
      expect(lateDebt.isRepaidLate, isTrue);
      expect(lateDebt.daysLateRepaid, equals(3));
    });
  });
}
