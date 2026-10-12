import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';
import 'expense.dart';

/// Server-side filters for the transaction history and exports.
/// Free-text search is applied client-side (Firestore has no full-text
/// search); see `ExpenseSearch`.
class ExpenseFilter extends Equatable {
  const ExpenseFilter({
    this.range,
    this.categoryId,
    this.paymentMethod,
    this.newestFirst = true,
  });

  final DateRange? range;
  final String? categoryId;
  final PaymentMethod? paymentMethod;
  final bool newestFirst;

  bool get hasFilters =>
      range != null || categoryId != null || paymentMethod != null;

  ExpenseFilter copyWith({
    DateRange? Function()? range,
    String? Function()? categoryId,
    PaymentMethod? Function()? paymentMethod,
    bool? newestFirst,
  }) {
    return ExpenseFilter(
      range: range != null ? range() : this.range,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      paymentMethod: paymentMethod != null
          ? paymentMethod()
          : this.paymentMethod,
      newestFirst: newestFirst ?? this.newestFirst,
    );
  }

  @override
  List<Object?> get props => [range, categoryId, paymentMethod, newestFirst];
}

abstract final class ExpenseSearch {
  static bool matches(Expense e, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (e.note?.toLowerCase().contains(q) ?? false) ||
        (e.merchant?.toLowerCase().contains(q) ?? false);
  }
}
