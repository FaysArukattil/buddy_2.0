// lib/models/debt.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class DebtModel {
  final String? id;
  final String type; // 'lend' (I lent to friend) or 'borrow' (I borrowed from friend)
  final String personName;
  final double amount;
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

  DebtModel({
    this.id,
    required this.type,
    required this.personName,
    required this.amount,
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
  });

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

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'personName': personName,
      'amount': amount,
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
    };
  }

  factory DebtModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DebtModel(
      id: doc.id,
      type: data['type'] as String? ?? 'lend',
      personName: data['personName'] as String? ?? 'Friend',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'personName': personName,
      'amount': amount,
      'date': date.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'isRepaid': isRepaid,
      'repaidDate': repaidDate?.toIso8601String(),
      'note': note,
      'transactionId': transactionId,
      'repaymentTransactionId': repaymentTransactionId,
      'remindOnDueDate': remindOnDueDate,
      'notificationId': notificationId,
    };
  }

  factory DebtModel.fromMap(Map<String, dynamic> map) {
    return DebtModel(
      id: map['id'] as String?,
      type: map['type'] as String? ?? 'lend',
      personName: map['personName'] as String? ?? 'Friend',
      amount: (map['amount'] as num).toDouble(),
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
    );
  }

  DebtModel copyWith({
    String? id,
    String? type,
    String? personName,
    double? amount,
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
  }) {
    return DebtModel(
      id: id ?? this.id,
      type: type ?? this.type,
      personName: personName ?? this.personName,
      amount: amount ?? this.amount,
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
    );
  }
}
