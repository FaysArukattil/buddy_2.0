class Bill {
  final String id;
  final String name;
  final double amount;
  final DateTime dueDate;
  final String category;
  final bool isPaid;
  final String? note;

  Bill({
    required this.id,
    required this.name,
    required this.amount,
    required this.dueDate,
    required this.category,
    this.isPaid = false,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'dueDate': dueDate.toIso8601String(),
      'category': category,
      'isPaid': isPaid,
      'note': note,
    };
  }

  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'],
      name: map['name'],
      amount: map['amount'],
      dueDate: DateTime.parse(map['dueDate']),
      category: map['category'],
      isPaid: map['isPaid'] ?? false,
      note: map['note'],
    );
  }

  Bill copyWith({
    String? id,
    String? name,
    double? amount,
    DateTime? dueDate,
    String? category,
    bool? isPaid,
    String? note,
  }) {
    return Bill(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      category: category ?? this.category,
      isPaid: isPaid ?? this.isPaid,
      note: note ?? this.note,
    );
  }
}
