// lib/models/debt.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// A single partial payment event stored inside a debt record
class DebtSettlement {
  final double amount;
  final DateTime date;
  final String? note;

  const DebtSettlement({
    required this.amount,
    required this.date,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'date': Timestamp.fromDate(date),
        'note': note,
      };

  factory DebtSettlement.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    final rawDate = map['date'];
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }
    return DebtSettlement(
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      date: parsedDate,
      note: map['note'] as String?,
    );
  }
}

class DebtModel {
  final String? id;
  final String type; // 'lend' (I lent to friend) or 'borrow' (I borrowed from friend)
  final String personName;
  final double amount;       // remaining unpaid amount
  final double originalAmount; // original amount when the debt was first created
  final DateTime date;
  final DateTime dueDate;
  final bool isRepaid;
  final DateTime? repaidDate;
  final String? note;
  final String? transactionId;
  final String? repaymentTransactionId;
  final bool remindOnDueDate;
  final int? notificationId;
  final DateTime? createdAt;
  final List<DebtSettlement> settlements; // history of partial payments

  DebtModel({
    this.id,
    required this.type,
    required this.personName,
    required this.amount,
    double? originalAmount,
    required this.date,
    required this.dueDate,
    this.isRepaid = false,
    this.repaidDate,
    this.note,
    this.transactionId,
    this.repaymentTransactionId,
    this.remindOnDueDate = true,
    this.notificationId,
    this.createdAt,
    List<DebtSettlement>? settlements,
  })  : originalAmount = originalAmount ?? amount,
        settlements = settlements ?? [];

  bool get isLend => type.toLowerCase() == 'lend';
  bool get isBorrow => type.toLowerCase() == 'borrow';

  bool get isDueToday {
    if (isRepaid) return false;
    final now = DateTime.now();
    return dueDate.year == now.year &&
        dueDate.month == now.month &&
        dueDate.day == now.day;
  }

  bool get isOverdue {
    if (isRepaid) return false;
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final dueMidnight = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return dueMidnight.isBefore(todayMidnight);
  }

  int get daysDifference {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final dueMidnight = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return dueMidnight.difference(todayMidnight).inDays;
  }

  /// Total amount settled so far (from settlements list or computed from remaining)
  double get totalSettled => settlements.isNotEmpty
      ? settlements.fold(0.0, (s, e) => s + e.amount)
      : (isRepaid
          ? originalAmount
          : (originalAmount - amount).clamp(0.0, originalAmount));

  /// Remaining balance
  double get remainingAmount => amount;

  /// Total amount paid so far
  double get totalPaid => totalSettled;

  /// Repayment progress (0.0 to 1.0)
  double get progressPercent => originalAmount > 0
      ? (totalPaid / originalAmount).clamp(0.0, 1.0)
      : (isRepaid ? 1.0 : 0.0);

  /// Has any partial settlements been recorded
  bool get hasPartialSettlements =>
      settlements.isNotEmpty || (amount < originalAmount && !isRepaid);

  /// Was the debt settled on or before the due date?
  bool get isRepaidOnTime {
    if (!isRepaid || repaidDate == null) return false;
    final dueMidnight = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final repaidMidnight =
        DateTime(repaidDate!.year, repaidDate!.month, repaidDate!.day);
    return !repaidMidnight.isAfter(dueMidnight);
  }

  /// Was the debt settled after the due date?
  bool get isRepaidLate {
    if (!isRepaid || repaidDate == null) return false;
    final dueMidnight = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final repaidMidnight =
        DateTime(repaidDate!.year, repaidDate!.month, repaidDate!.day);
    return repaidMidnight.isAfter(dueMidnight);
  }

  /// Number of days repaid late (0 if on time or not settled)
  int get daysLateRepaid {
    if (!isRepaidLate || repaidDate == null) return 0;
    final dueMidnight = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final repaidMidnight =
        DateTime(repaidDate!.year, repaidDate!.month, repaidDate!.day);
    return repaidMidnight.difference(dueMidnight).inDays;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'personName': personName,
      'amount': amount,
      'originalAmount': originalAmount,
      'date': Timestamp.fromDate(date),
      'dueDate': Timestamp.fromDate(dueDate),
      'isRepaid': isRepaid,
      'repaidDate':
          repaidDate != null ? Timestamp.fromDate(repaidDate!) : null,
      'note': note,
      'transactionId': transactionId,
      'repaymentTransactionId': repaymentTransactionId,
      'remindOnDueDate': remindOnDueDate,
      'notificationId': notificationId,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'settlements': settlements.map((s) => s.toMap()).toList(),
    };
  }

  factory DebtModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawSettlements = data['settlements'] as List<dynamic>? ?? [];
    return DebtModel(
      id: doc.id,
      type: data['type'] as String? ?? 'lend',
      personName: data['personName'] as String? ?? 'Friend',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      originalAmount: (data['originalAmount'] as num?)?.toDouble() ??
          (data['amount'] as num?)?.toDouble() ??
          0.0,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dueDate: (data['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRepaid: data['isRepaid'] as bool? ?? false,
      repaidDate: (data['repaidDate'] as Timestamp?)?.toDate(),
      note: data['note'] as String?,
      transactionId: data['transactionId'] as String?,
      repaymentTransactionId: data['repaymentTransactionId'] as String?,
      remindOnDueDate: data['remindOnDueDate'] as bool? ?? true,
      notificationId: (data['notificationId'] as num?)?.toInt(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      settlements: rawSettlements
          .map((e) => DebtSettlement.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'personName': personName,
      'amount': amount,
      'originalAmount': originalAmount,
      'date': date.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'isRepaid': isRepaid,
      'repaidDate': repaidDate?.toIso8601String(),
      'note': note,
      'transactionId': transactionId,
      'repaymentTransactionId': repaymentTransactionId,
      'remindOnDueDate': remindOnDueDate,
      'notificationId': notificationId,
      'settlements': settlements.map((s) => s.toMap()).toList(),
    };
  }

  factory DebtModel.fromMap(Map<String, dynamic> map) {
    final rawSettlements = map['settlements'] as List<dynamic>? ?? [];
    return DebtModel(
      id: map['id'] as String?,
      type: map['type'] as String? ?? 'lend',
      personName: map['personName'] as String? ?? 'Friend',
      amount: (map['amount'] as num).toDouble(),
      originalAmount: (map['originalAmount'] as num?)?.toDouble() ??
          (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      dueDate: DateTime.parse(map['dueDate'] as String),
      isRepaid: map['isRepaid'] as bool? ?? false,
      repaidDate: map['repaidDate'] != null
          ? DateTime.parse(map['repaidDate'] as String)
          : null,
      note: map['note'] as String?,
      transactionId: map['transactionId'] as String?,
      repaymentTransactionId: map['repaymentTransactionId'] as String?,
      remindOnDueDate: map['remindOnDueDate'] as bool? ?? true,
      notificationId: (map['notificationId'] as num?)?.toInt(),
      settlements: rawSettlements
          .map((e) => DebtSettlement.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  DebtModel copyWith({
    String? id,
    String? type,
    String? personName,
    double? amount,
    double? originalAmount,
    DateTime? date,
    DateTime? dueDate,
    bool? isRepaid,
    DateTime? repaidDate,
    String? note,
    String? transactionId,
    String? repaymentTransactionId,
    bool? remindOnDueDate,
    int? notificationId,
    DateTime? createdAt,
    List<DebtSettlement>? settlements,
  }) {
    return DebtModel(
      id: id ?? this.id,
      type: type ?? this.type,
      personName: personName ?? this.personName,
      amount: amount ?? this.amount,
      originalAmount: originalAmount ?? this.originalAmount,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      isRepaid: isRepaid ?? this.isRepaid,
      repaidDate: repaidDate ?? this.repaidDate,
      note: note ?? this.note,
      transactionId: transactionId ?? this.transactionId,
      repaymentTransactionId:
          repaymentTransactionId ?? this.repaymentTransactionId,
      remindOnDueDate: remindOnDueDate ?? this.remindOnDueDate,
      notificationId: notificationId ?? this.notificationId,
      createdAt: createdAt ?? this.createdAt,
      settlements: settlements ?? this.settlements,
    );
  }
}
