import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/utils/icon_helper.dart';
import 'package:buddy/services/preference_service.dart';

void main() {
  group('TransactionModel Note Cleaning Tests', () {
    test('cleanNoteText strips auto-detected prefixes', () {
      expect(
        TransactionModel.cleanNoteText('Auto-detected: Paid to Swiggy'),
        equals('Paid to Swiggy'),
      );
      expect(
        TransactionModel.cleanNoteText('Auto-detected from SMS: Starbucks coffee'),
        equals('Starbucks coffee'),
      );
      expect(
        TransactionModel.cleanNoteText('Auto-detected notification: Zomato'),
        equals('Zomato'),
      );
      expect(
        TransactionModel.cleanNoteText('AutoDetection: Uber ride'),
        equals('Uber ride'),
      );
      expect(
        TransactionModel.cleanNoteText('auto detected : Petrol bunk'),
        equals('Petrol bunk'),
      );
    });

    test('cleanNoteText preserves regular notes and handles edge cases', () {
      expect(
        TransactionModel.cleanNoteText('Dinner with friends'),
        equals('Dinner with friends'),
      );
      expect(TransactionModel.cleanNoteText(null), isNull);
      expect(TransactionModel.cleanNoteText('   '), isNull);
      expect(TransactionModel.cleanNoteText('Auto-detected:   '), isNull);
      expect(TransactionModel.cleanNoteText('Auto-detected'), isNull);
    });

    test('displayTitle returns cleanNote if available, falls back to category', () {
      final txnWithAutoNote = TransactionModel(
        id: '1',
        amount: 150.0,
        type: 'Expense',
        category: 'Food',
        icon: 983304,
        date: DateTime(2026, 10, 14, 12, 0),
        note: 'Auto-detected: Pizza place',
        autoDetected: true,
      );
      expect(txnWithAutoNote.cleanNote, equals('Pizza place'));
      expect(txnWithAutoNote.displayTitle, equals('Pizza place'));

      final txnWithoutNote = TransactionModel(
        id: '2',
        amount: 50.0,
        type: 'Expense',
        category: 'Travel',
        icon: 63155,
        date: DateTime(2026, 10, 14, 12, 0),
        note: null,
      );
      expect(txnWithoutNote.cleanNote, isNull);
      expect(txnWithoutNote.displayTitle, equals('Travel'));
    });
  });

  group('TransactionModel Deduplication Tests', () {
    test('deduplicates identical IDs', () {
      final t1 = TransactionModel(
        id: 'txn-1',
        amount: 200,
        type: 'Expense',
        category: 'Shopping',
        icon: 983409,
        date: DateTime(2026, 10, 14, 10, 30),
      );
      final t2 = TransactionModel(
        id: 'txn-1',
        amount: 200,
        type: 'Expense',
        category: 'Shopping',
        icon: 983409,
        date: DateTime(2026, 10, 14, 10, 30),
      );

      final deduped = TransactionModel.deduplicate([t1, t2]);
      expect(deduped.length, equals(1));
      expect(deduped.first.id, equals('txn-1'));
    });

    test('deduplicates by notification hash even if IDs differ', () {
      final t1 = TransactionModel(
        id: 'firestore-doc-a',
        amount: 450,
        type: 'Expense',
        category: 'Groceries',
        icon: 983409,
        date: DateTime(2026, 10, 14, 11, 0),
        notificationHash: 'hash-abc-123',
        autoDetected: true,
      );
      final t2 = TransactionModel(
        id: 'firestore-doc-b',
        amount: 450,
        type: 'Expense',
        category: 'Groceries',
        icon: 983409,
        date: DateTime(2026, 10, 14, 11, 0),
        notificationHash: 'hash-abc-123',
        autoDetected: true,
      );

      final deduped = TransactionModel.deduplicate([t1, t2]);
      expect(deduped.length, equals(1));
    });

    test('deduplicates duplicate manual/auto entries with matching signature in same minute', () {
      final t1 = TransactionModel(
        id: 'auto-doc-1',
        amount: 100,
        type: 'Expense',
        category: 'Food',
        icon: 983304,
        date: DateTime(2026, 10, 14, 14, 15, 10),
        note: 'Auto-detected: Cafe',
        autoDetected: true,
      );
      final t2 = TransactionModel(
        id: 'manual-doc-2',
        amount: 100,
        type: 'Expense',
        category: 'Food',
        icon: 983304,
        date: DateTime(2026, 10, 14, 14, 15, 25),
        note: 'Cafe',
        autoDetected: false,
      );

      final deduped = TransactionModel.deduplicate([t1, t2]);
      expect(deduped.length, equals(1));
    });

    test('preserves legitimate distinct transactions', () {
      final t1 = TransactionModel(
        id: 't-1',
        amount: 100,
        type: 'Expense',
        category: 'Food',
        icon: 983304,
        date: DateTime(2026, 10, 14, 10, 0),
      );
      final t2 = TransactionModel(
        id: 't-2',
        amount: 100,
        type: 'Income',
        category: 'Salary',
        icon: 983128,
        date: DateTime(2026, 10, 14, 10, 0),
      );
      final t3 = TransactionModel(
        id: 't-3',
        amount: 250,
        type: 'Expense',
        category: 'Food',
        icon: 983304,
        date: DateTime(2026, 10, 14, 10, 0),
      );

      final deduped = TransactionModel.deduplicate([t1, t2, t3]);
      expect(deduped.length, equals(3));
    });
  });

  group('IconHelper Icon Mapping Tests', () {
    test('legacy 983074 codepoint maps to category_rounded', () {
      final icon = IconHelper.getIcon(983074);
      expect(icon, equals(Icons.category_rounded));
    });

    test('other fallback maps to category_rounded', () {
      final icon = IconHelper.getIcon(null);
      expect(icon, equals(Icons.category_rounded));
    });
  });

  group('PreferenceService Tests', () {
    test('notifies listeners and saves preference', () async {
      SharedPreferences.setMockInitialValues({});
      await PreferenceService.init();

      expect(PreferenceService.includeDebtsInHome, isTrue);

      bool notified = false;
      void listener() {
        notified = true;
      }

      PreferenceService.includeDebtsInHomeNotifier.addListener(listener);

      await PreferenceService.setIncludeDebtsInHome(false);
      expect(PreferenceService.includeDebtsInHome, isFalse);
      expect(notified, isTrue);

      PreferenceService.includeDebtsInHomeNotifier.removeListener(listener);
    });
  });
}
