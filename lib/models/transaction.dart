// lib/models/transaction.dart
class TransactionModel {
  final int? id;
  final double amount;
  final String type; // 'expense' or 'income'
  final DateTime date;
  final String? note;
  final String category;
  final int icon;
  final bool autoDetected;
  final String? notificationSource;
  final String? notificationHash;

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
  });

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'type': type,
      'date': date.toIso8601String(),
      'note': note,
      'category': category,
      'icon': icon,
      'auto_detected': autoDetected ? 1 : 0,
      'notification_source': notificationSource,
      'notification_hash': notificationHash,
    };
  }

  factory TransactionModel.fromMap(Map<String, Object?> map) {
    return TransactionModel(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String?,
      category: map['category'] as String,
      icon: (map['icon'] as num).toInt(),
      autoDetected:
          (map['auto_detected'] == 1) || (map['auto_detected'] == true),
      notificationSource: map['notification_source'] as String?,
      notificationHash: map['notification_hash'] as String?,
    );
  }
}
