import 'package:daily/core/dates/local_date.dart';
import 'package:daily/domain/models/loan.dart';
import 'package:flutter_test/flutter_test.dart';

Loan _loan({
  String id = 'l1',
  LoanDirection direction = LoanDirection.lent,
  int amount = 100000,
  int repaid = 0,
  String currency = 'INR',
  LocalDate? due,
  bool settled = false,
}) => Loan(
  id: id,
  direction: direction,
  personName: 'Rahul',
  amountMinor: amount,
  repaidMinor: repaid,
  currencyCode: currency,
  date: LocalDate(2025, 10, 1),
  dueDate: due,
  settled: settled,
);

void main() {
  final today = LocalDate(2025, 10, 14);

  test('repayments reduce what is owed and settle the loan when complete', () {
    var l = _loan(amount: 100000);
    l = l.withRepayment(40000);
    expect(l.outstandingMinor, 60000);
    expect(l.settled, isFalse);
    expect(l.progress, closeTo(0.4, 1e-9));

    l = l.withRepayment(60000);
    expect(l.outstandingMinor, 0);
    expect(l.settled, isTrue);

    // Over-paying never pushes repaid above the amount.
    expect(_loan(amount: 100).withRepayment(500).repaidMinor, 100);
  });

  test('overdue only when open and past the due date', () {
    expect(_loan(due: LocalDate(2025, 10, 13)).isOverdue(today), isTrue);
    expect(_loan(due: today).isOverdue(today), isFalse);
    expect(_loan().isOverdue(today), isFalse);
    expect(
      _loan(due: LocalDate(2025, 10, 1), settled: true).isOverdue(today),
      isFalse,
    );
  });

  test('totals split money to receive and to pay, per currency', () {
    final t = LoanTotals.of(
      [
        _loan(id: 'a', amount: 50000, repaid: 10000),
        _loan(id: 'b', amount: 20000, due: LocalDate(2025, 10, 2)),
        _loan(id: 'c', direction: LoanDirection.borrowed, amount: 30000),
        _loan(id: 'd', amount: 99999, settled: true),
        _loan(id: 'e', amount: 70000, currency: 'USD'),
      ],
      'INR',
      today,
    );
    expect(t.toReceiveMinor, 60000);
    expect(t.toPayMinor, 30000);
    expect(t.openCount, 3);
    expect(t.overdueCount, 1);
  });
}
