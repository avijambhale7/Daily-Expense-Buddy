import 'package:equatable/equatable.dart';

/// An expense category.
///
/// Built-in categories are defined in code ([DefaultCategories]) and do not
/// need to be written to the database. When a user renames, recolours or
/// archives a built-in category, an override document with the same id is
/// stored. Custom categories are stored with generated ids.
///
/// Categories are never hard-deleted while expenses reference them; they are
/// archived instead, so historical reports keep their names and colours.
class ExpenseCategory extends Equatable {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorIndex,
    this.isBuiltIn = false,
    this.isArchived = false,
    this.sortOrder = 100,
  });

  static const int maxNameLength = 40;
  static const int paletteSize = 12;
  static const String fallbackId = 'other';

  final String id;
  final String name;

  /// Key into the icon catalogue (see `CategoryIcons`).
  final String iconKey;

  /// Index into the theme's categorical colour palette (0–11). Colours are
  /// resolved by the active theme so they adapt to light/dark modes.
  final int colorIndex;
  final bool isBuiltIn;
  final bool isArchived;
  final int sortOrder;

  ExpenseCategory copyWith({
    String? name,
    String? iconKey,
    int? colorIndex,
    bool? isArchived,
    int? sortOrder,
  }) {
    return ExpenseCategory(
      id: id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorIndex: colorIndex ?? this.colorIndex,
      isBuiltIn: isBuiltIn,
      isArchived: isArchived ?? this.isArchived,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Placeholder used when an expense references a category id that no
  /// longer exists (e.g. removed on another device).
  static ExpenseCategory unknown(String id) => ExpenseCategory(
    id: id,
    name: 'Uncategorized',
    iconKey: 'other',
    colorIndex: 11,
    isArchived: true,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    iconKey,
    colorIndex,
    isBuiltIn,
    isArchived,
    sortOrder,
  ];
}

abstract final class DefaultCategories {
  static const List<ExpenseCategory> all = [
    ExpenseCategory(
      id: 'food',
      name: 'Food and Drinks',
      iconKey: 'food',
      colorIndex: 1,
      isBuiltIn: true,
      sortOrder: 0,
    ),
    ExpenseCategory(
      id: 'transport',
      name: 'Transportation',
      iconKey: 'transport',
      colorIndex: 0,
      isBuiltIn: true,
      sortOrder: 1,
    ),
    ExpenseCategory(
      id: 'groceries',
      name: 'Groceries',
      iconKey: 'groceries',
      colorIndex: 2,
      isBuiltIn: true,
      sortOrder: 2,
    ),
    ExpenseCategory(
      id: 'shopping',
      name: 'Shopping',
      iconKey: 'shopping',
      colorIndex: 4,
      isBuiltIn: true,
      sortOrder: 3,
    ),
    ExpenseCategory(
      id: 'bills',
      name: 'Bills and Utilities',
      iconKey: 'bills',
      colorIndex: 3,
      isBuiltIn: true,
      sortOrder: 4,
    ),
    ExpenseCategory(
      id: 'entertainment',
      name: 'Entertainment',
      iconKey: 'entertainment',
      colorIndex: 6,
      isBuiltIn: true,
      sortOrder: 5,
    ),
    ExpenseCategory(
      id: 'health',
      name: 'Health',
      iconKey: 'health',
      colorIndex: 7,
      isBuiltIn: true,
      sortOrder: 6,
    ),
    ExpenseCategory(
      id: 'education',
      name: 'Education',
      iconKey: 'education',
      colorIndex: 5,
      isBuiltIn: true,
      sortOrder: 7,
    ),
    ExpenseCategory(
      id: 'travel',
      name: 'Travel',
      iconKey: 'travel',
      colorIndex: 8,
      isBuiltIn: true,
      sortOrder: 8,
    ),
    ExpenseCategory(
      id: 'housing',
      name: 'Housing',
      iconKey: 'housing',
      colorIndex: 9,
      isBuiltIn: true,
      sortOrder: 9,
    ),
    ExpenseCategory(
      id: 'personal_care',
      name: 'Personal Care',
      iconKey: 'personal_care',
      colorIndex: 10,
      isBuiltIn: true,
      sortOrder: 10,
    ),
    ExpenseCategory(
      id: 'other',
      name: 'Other',
      iconKey: 'other',
      colorIndex: 11,
      isBuiltIn: true,
      sortOrder: 11,
    ),
  ];

  static bool isBuiltInId(String id) => all.any((c) => c.id == id);

  /// Merges built-in categories with stored overrides and custom categories.
  static List<ExpenseCategory> merge(List<ExpenseCategory> stored) {
    final byId = {for (final c in all) c.id: c};
    for (final s in stored) {
      final base = byId[s.id];
      byId[s.id] = base == null
          ? s
          : base.copyWith(
              name: s.name,
              iconKey: s.iconKey,
              colorIndex: s.colorIndex,
              isArchived: s.isArchived,
              sortOrder: s.sortOrder,
            );
    }
    final list = byId.values.toList()
      ..sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0
            ? o
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }
}
