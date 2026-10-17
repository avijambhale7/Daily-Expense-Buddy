import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';
import 'expense.dart';

/// Server-side filters for the transaction history and exports.
/// Free-text search is applied client-side (Firestore has no full-text
/// search); see `ExpenseSearch`.
class ExpenseFilter extends Equatable {
  const ExpenseFilter({
    this.range,
    this.categoryIds = const {},
    this.paymentMethods = const {},
    this.newestFirst = true,
  });

  /// Firestore allows at most this many value combinations
  /// (categories × payment methods) in one query.
  static const maxCombinations = 30;

  final DateRange? range;

  /// Expenses in any of these categories; empty means all categories.
  final Set<String> categoryIds;

  /// Expenses paid with any of these methods; empty means any method.
  final Set<PaymentMethod> paymentMethods;
  final bool newestFirst;

  bool get hasFilters =>
      range != null || categoryIds.isNotEmpty || paymentMethods.isNotEmpty;

  /// Value combinations this filter sends to Firestore.
  int get combinations =>
      (categoryIds.isEmpty ? 1 : categoryIds.length) *
      (paymentMethods.isEmpty ? 1 : paymentMethods.length);

  ExpenseFilter copyWith({
    DateRange? Function()? range,
    Set<String>? categoryIds,
    Set<PaymentMethod>? paymentMethods,
    bool? newestFirst,
  }) {
    return ExpenseFilter(
      range: range != null ? range() : this.range,
      categoryIds: categoryIds ?? this.categoryIds,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      newestFirst: newestFirst ?? this.newestFirst,
    );
  }

  @override
  List<Object?> get props => [range, categoryIds, paymentMethods, newestFirst];
}

abstract final class ExpenseSearch {
  static bool matches(Expense e, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (e.note?.toLowerCase().contains(q) ?? false) ||
        (e.merchant?.toLowerCase().contains(q) ?? false);
  }
}
