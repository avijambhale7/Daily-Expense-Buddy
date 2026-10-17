import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';

/// A premium savings target, e.g. "Save ₹10,000 by Diwali". Stored at
/// `users/{uid}/goals/{id}`. Money "saved" here is just a record; it is not
/// an expense and doesn't change any report.
class SavingsGoal extends Equatable {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetMinor,
    required this.currencyCode,
    this.savedMinor = 0,
    this.targetDate,
  });

  final String id;
  final String name;
  final int targetMinor;
  final int savedMinor;
  final String currencyCode;
  final LocalDate? targetDate;

  bool get reached => savedMinor >= targetMinor;
  int get remainingMinor =>
      savedMinor >= targetMinor ? 0 : targetMinor - savedMinor;

  /// 0–1.
  double get progress =>
      targetMinor <= 0 ? 0 : (savedMinor / targetMinor).clamp(0, 1).toDouble();

  /// How much to put aside each day to reach the target on time (rounded
  /// up), or null without a target date, once reached, or when overdue.
  int? perDayMinor(LocalDate today) {
    final date = targetDate;
    if (date == null || reached || date < today) return null;
    final days = date.daysSince(today) + 1;
    return (remainingMinor + days - 1) ~/ days;
  }

  /// Adds (positive) or takes out (negative) money; never below zero.
  SavingsGoal withChange(int minor) {
    final next = savedMinor + minor;
    return copyWith(savedMinor: next < 0 ? 0 : next);
  }

  SavingsGoal copyWith({
    String? name,
    int? targetMinor,
    int? savedMinor,
    LocalDate? Function()? targetDate,
  }) => SavingsGoal(
    id: id,
    name: name ?? this.name,
    targetMinor: targetMinor ?? this.targetMinor,
    savedMinor: savedMinor ?? this.savedMinor,
    currencyCode: currencyCode,
    targetDate: targetDate != null ? targetDate() : this.targetDate,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    targetMinor,
    savedMinor,
    currencyCode,
    targetDate,
  ];
}
