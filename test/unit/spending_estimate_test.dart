import 'package:daily/core/dates/local_date.dart';
import 'package:daily/domain/models/expense.dart';
import 'package:daily/domain/services/spending_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _e(LocalDate d, int amount, {String currency = 'USD'}) => Expense(
  id: '${d.toIso()}-$amount',
  amountMinor: amount,
  currencyCode: currency,
  categoryId: 'food',
  date: d,
);

void main() {
  final month = DateRange(LocalDate(2025, 10, 1), LocalDate(2025, 10, 31));

  test('average per day so far × days in the month', () {
    final e = SpendingEstimate.of(
      range: month,
      today: LocalDate(2025, 10, 10),
      expenses: [
        _e(LocalDate(2025, 10, 1), 5000),
        _e(LocalDate(2025, 10, 10), 5000),
        // Ignored: other currency, and outside the period.
        _e(LocalDate(2025, 10, 5), 99999, currency: 'EUR'),
        _e(LocalDate(2025, 9, 30), 99999),
      ],
      currencyCode: 'USD',
    );
    expect(e.spentMinor, 10000);
    expect(e.elapsedDays, 10);
    expect(e.avgPerDayMinor, 1000);
    expect(e.estimatedMinor, 31000);
  });

  test('a week projects over 7 days; an ended period is just its total', () {
    final week = DateRange(LocalDate(2025, 10, 13), LocalDate(2025, 10, 19));
    final now = SpendingEstimate.of(
      range: week,
      today: LocalDate(2025, 10, 14),
      expenses: [_e(LocalDate(2025, 10, 13), 3000)],
      currencyCode: 'USD',
    );
    expect(now.estimatedMinor, 10500);

    final past = SpendingEstimate.of(
      range: week,
      today: LocalDate(2025, 11, 1),
      expenses: [_e(LocalDate(2025, 10, 13), 3000)],
      currencyCode: 'USD',
    );
    expect(past.estimatedMinor, 3000);
  });
}
