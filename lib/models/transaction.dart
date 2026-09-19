// lib/models/transaction.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String? id;
  final double amount;
  final String type; // 'expense' or 'income'
  final DateTime date;
  final String? note;
  final String category;
  final int icon;
  final bool autoDetected;
  final String? notificationSource;
  final String? notificationHash;
  final DateTime? createdAt;

  TransactionModel({
    this.id,
    required this.amount,
    required this.type,
    required this.date,
    this.note,
    required this.category,
    required this.icon,
    this.autoDetected = false,
    this.notificationSource,
    this.notificationHash,
    this.createdAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'type': type,
      'date': Timestamp.fromDate(date),
      'note': note,
      'category': category,
      'icon': icon,
      'autoDetected': autoDetected,
      'notificationSource': notificationSource,
      'notificationHash': notificationHash,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransactionModel(
      id: doc.id,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      type: data['type'] as String? ?? 'expense',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: data['note'] as String?,
      category: data['category'] as String? ?? 'Other',
      icon: (data['icon'] as num?)?.toInt() ?? 0xe237,
      autoDetected: data['autoDetected'] as bool? ?? false,
      notificationSource: data['notificationSource'] as String?,
      notificationHash: data['notificationHash'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// For backward compat with screens that use `Map<String, dynamic>`
  Map<String, dynamic> toDisplayMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'date': date,
      'note': note,
      'category': category,
      'icon': icon,
      'auto_detected': autoDetected,
      'notificationSource': notificationSource,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'date': date.toIso8601String(),
      'note': note,
      'category': category,
      'icon': icon,
      'autoDetected': autoDetected,
      'notificationSource': notificationSource,
      'notificationHash': notificationHash,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as String?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String?,
      category: map['category'] as String,
      icon: (map['icon'] as num).toInt(),
      autoDetected: map['autoDetected'] as bool? ?? false,
      notificationSource: map['notificationSource'] as String?,
      notificationHash: map['notificationHash'] as String?,
    );
  }

  TransactionModel copyWith({
    String? id,
    double? amount,
    String? type,
    DateTime? date,
    String? note,
    String? category,
    int? icon,
    bool? autoDetected,
    String? notificationSource,
    String? notificationHash,
    DateTime? createdAt,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      date: date ?? this.date,
      note: note ?? this.note,
      category: category ?? this.category,
      icon: icon ?? this.icon,
      autoDetected: autoDetected ?? this.autoDetected,
      notificationSource: notificationSource ?? this.notificationSource,
      notificationHash: notificationHash ?? this.notificationHash,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
