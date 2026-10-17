import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';
import 'expense.dart';

enum RecurrenceFrequency {
  weekly('weekly', 'Every week'),
  monthly('monthly', 'Every month'),
  yearly('yearly', 'Every year');

  const RecurrenceFrequency(this.key, this.label);
  final String key;
  final String label;

  static RecurrenceFrequency? fromKey(Object? key) {
    for (final f in values) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// A premium template (rent, subscription, EMI…) that adds an expense on
/// every due date. Stored at `users/{uid}/recurring/{id}`.
class RecurringExpense extends Equatable {
  const RecurringExpense({
    required this.id,
    required this.amountMinor,
    required this.currencyCode,
    required this.categoryId,
    required this.frequency,
    required this.startDate,
    this.merchant,
    this.note,
    this.paymentMethod,
    this.lastPostedDate,
    this.active = true,
  });

  /// Most occurrences added in one go (e.g. after months offline), so a
  /// mistaken old start date can't flood the history.
  static const maxCatchUp = 24;

  final String id;
  final int amountMinor;
  final String currencyCode;
  final String categoryId;
  final RecurrenceFrequency frequency;

  /// First due date. Monthly and yearly repeats keep its day of the month,
  /// moved to the last day when a month is shorter (31st → 30th, 28th/29th).
  final LocalDate startDate;
  final String? merchant;
  final String? note;
  final PaymentMethod? paymentMethod;

  /// The latest due date already added as an expense.
  final LocalDate? lastPostedDate;

  /// Paused templates add nothing.
  final bool active;

  /// The [n]th due date (0 = [startDate]).
  LocalDate occurrence(int n) {
    switch (frequency) {
      case RecurrenceFrequency.weekly:
        return startDate.addDays(7 * n);
      case RecurrenceFrequency.monthly:
        return _sameDay(startDate.addMonths(n));
      case RecurrenceFrequency.yearly:
        return _sameDay(startDate.addMonths(12 * n));
    }
  }

  LocalDate _sameDay(LocalDate inMonth) {
    final last = LocalDate.daysInMonth(inMonth.year, inMonth.month);
    return LocalDate(
      inMonth.year,
      inMonth.month,
      startDate.day <= last ? startDate.day : last,
    );
  }

  /// Due dates not yet added, up to and including [today], oldest first.
  List<LocalDate> dueDates(LocalDate today) {
    if (!active) return const [];
    final result = <LocalDate>[];
    for (var n = 0; ; n++) {
      final d = occurrence(n);
      if (d > today) break;
      if (lastPostedDate == null || d > lastPostedDate!) result.add(d);
      if (n > 5000) break; // Guards against a corrupt start date.
    }
    // Only the most recent ones when far behind.
    return result.length > maxCatchUp
        ? result.sublist(result.length - maxCatchUp)
        : result;
  }

  /// The next date this template will add an expense, or null if paused.
  LocalDate? nextDate(LocalDate today) {
    if (!active) return null;
    for (var n = 0; n < 6000; n++) {
      final d = occurrence(n);
      if (d >= today && (lastPostedDate == null || d > lastPostedDate!)) {
        return d;
      }
    }
    return null;
  }

  /// Deterministic expense id, so two devices adding the same occurrence
  /// write the same document instead of a duplicate.
  String expenseIdFor(LocalDate date) => 'rec_${id}_${date.toIso()}';

  Expense expenseFor(LocalDate date) => Expense(
    id: expenseIdFor(date),
    amountMinor: amountMinor,
    currencyCode: currencyCode,
    categoryId: categoryId,
    date: date,
    merchant: merchant,
    note: note,
    paymentMethod: paymentMethod,
  );

  RecurringExpense copyWith({
    int? amountMinor,
    String? categoryId,
    RecurrenceFrequency? frequency,
    LocalDate? startDate,
    String? Function()? merchant,
    String? Function()? note,
    PaymentMethod? Function()? paymentMethod,
    LocalDate? Function()? lastPostedDate,
    bool? active,
  }) => RecurringExpense(
    id: id,
    amountMinor: amountMinor ?? this.amountMinor,
    currencyCode: currencyCode,
    categoryId: categoryId ?? this.categoryId,
    frequency: frequency ?? this.frequency,
    startDate: startDate ?? this.startDate,
    merchant: merchant != null ? merchant() : this.merchant,
    note: note != null ? note() : this.note,
    paymentMethod: paymentMethod != null ? paymentMethod() : this.paymentMethod,
    lastPostedDate: lastPostedDate != null
        ? lastPostedDate()
        : this.lastPostedDate,
    active: active ?? this.active,
  );

  @override
  List<Object?> get props => [
    id,
    amountMinor,
    currencyCode,
    categoryId,
    frequency,
    startDate,
    merchant,
    note,
    paymentMethod,
    lastPostedDate,
    active,
  ];
}
