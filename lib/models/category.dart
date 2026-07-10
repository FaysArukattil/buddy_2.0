import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Category {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String type; // 'income' or 'expense'
  final bool isDefault;
  final int order;

  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
    this.isDefault = false,
    this.order = 0,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'icon': icon.codePoint,
      'color': color.value,
      'type': type,
      'isDefault': isDefault,
      'order': order,
    };
  }

  factory Category.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Category(
      id: doc.id,
      name: data['name'] as String? ?? '',
      icon: IconData(
        // ignore: non_const_argument_for_const_parameter
        (data['icon'] as num?)?.toInt() ?? Icons.category_rounded.codePoint,
        fontFamily: 'MaterialIcons',
      ),
      color: Color(
        (data['color'] as num?)?.toInt() ?? 0xFF9E9E9E,
      ),
      type: data['type'] as String? ?? 'expense',
      isDefault: data['isDefault'] as bool? ?? false,
      order: (data['order'] as num?)?.toInt() ?? 0,
    );
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      icon: IconData(
        // ignore: non_const_argument_for_const_parameter
        (map['icon'] as num?)?.toInt() ?? Icons.category_rounded.codePoint,
        fontFamily: 'MaterialIcons',
      ),
      color: Color(
        (map['color'] as num?)?.toInt() ?? 0xFF9E9E9E,
      ),
      type: map['type'] as String? ?? 'expense',
      isDefault: map['isDefault'] as bool? ?? false,
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  Category copyWith({
    String? id,
    String? name,
    IconData? icon,
    Color? color,
    String? type,
    bool? isDefault,
    int? order,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      type: type ?? this.type,
      isDefault: isDefault ?? this.isDefault,
      order: order ?? this.order,
    );
  }
}
