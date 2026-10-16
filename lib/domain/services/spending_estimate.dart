import '../../core/dates/local_date.dart';
import '../models/expense.dart';

/// Projected spending for a whole week or month, from the pace so far.
class SpendingEstimate {
  const SpendingEstimate({
    required this.range,
    required this.spentMinor,
    required this.elapsedDays,
  });

  final DateRange range;

  /// Spent from the start of [range] up to and including today.
  final int spentMinor;

  /// Days of [range] up to and including today (at least 1).
  final int elapsedDays;

  int get totalDays => range.dayCount;
  int get avgPerDayMinor => (spentMinor / elapsedDays).round();

  /// Average per day so far × days in the whole period.
  int get estimatedMinor => (spentMinor / elapsedDays * totalDays).round();

  /// Only expenses in [currencyCode] count, as everywhere in reports.
  static SpendingEstimate of({
    required DateRange range,
    required LocalDate today,
    required Iterable<Expense> expenses,
    required String currencyCode,
  }) {
    final end = LocalDate.min(today, range.end);
    final elapsed = end < range.start ? 1 : end.daysSince(range.start) + 1;
    final soFar = DateRange(range.start, end);
    var spent = 0;
    for (final e in expenses) {
      if (e.currencyCode == currencyCode && soFar.contains(e.date)) {
        spent += e.amountMinor;
      }
    }
    return SpendingEstimate(
      range: range,
      spentMinor: spent,
      elapsedDays: elapsed,
    );
  }
}
