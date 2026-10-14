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

  /// Safely strips "Auto-detected:" or similar prefixes from transaction note text
  static String? cleanNoteText(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final regex = RegExp(
      r'^(?:Auto[- ]?detected(?:\s*(?:from\s+)?(?:notification|sms|app))?|AutoDetection)[\s:–—\-]*',
      caseSensitive: false,
    );
    final stripped = trimmed.replaceFirst(regex, '').trim();
    return stripped.isNotEmpty ? stripped : null;
  }

  /// Note stripped of any "Auto-detected:" prefix
  String? get cleanNote => cleanNoteText(note);

  /// Clean title to display in transaction lists and cards
  String get displayTitle => cleanNote ?? category;

  /// Deduplicate a list of transactions in-memory.
  /// Deduplicates by:
  /// 1) Document ID (if present)
  /// 2) Notification Hash (if present)
  /// 3) Exact duplicate signature: amount + type + category + cleanNote + minute bucket
  static List<TransactionModel> deduplicate(List<TransactionModel> transactions) {
    if (transactions.isEmpty) return [];

    final seenIds = <String>{};
    final seenHashes = <String>{};
    final seenSignatures = <String>{};
    final result = <TransactionModel>[];

    for (final txn in transactions) {
      // 1. Doc ID deduplication
      if (txn.id != null && txn.id!.isNotEmpty) {
        if (seenIds.contains(txn.id)) continue;
        seenIds.add(txn.id!);
      }

      // 2. Notification hash deduplication
      final hash = txn.notificationHash?.trim();
      if (hash != null && hash.isNotEmpty) {
        if (seenHashes.contains(hash)) continue;
        seenHashes.add(hash);
      }

      // 3. Signature deduplication for same-minute duplicate additions
      final clean = txn.cleanNote ?? '';
      final minuteBucket = DateTime(
        txn.date.year,
        txn.date.month,
        txn.date.day,
        txn.date.hour,
        txn.date.minute,
      ).millisecondsSinceEpoch;
      final signature =
          '${txn.type.toLowerCase().trim()}_${txn.category.toLowerCase().trim()}_${txn.amount.toStringAsFixed(2)}_${clean.toLowerCase()}_$minuteBucket';

      if (seenSignatures.contains(signature)) {
        continue;
      }
      seenSignatures.add(signature);

      result.add(txn);
    }

    return result;
  }

  /// For backward compat with screens that use `Map<String, dynamic>`
  Map<String, dynamic> toDisplayMap() {
    final cn = cleanNote;
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'date': date,
      'note': cn ?? note,
      'raw_note': note,
      'title': displayTitle,
      'category': category,
      'icon': icon,
      'auto_detected': autoDetected,
      'autoDetected': autoDetected,
      'notificationSource': notificationSource,
      'notificationHash': notificationHash,
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
