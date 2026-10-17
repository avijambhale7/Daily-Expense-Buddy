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
  bool cancelled = false,
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
  cancelled: cancelled,
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
  });

  test('over-payments and non-positive repayments are rejected', () {
    expect(() => _loan(amount: 100).withRepayment(101), throwsArgumentError);
    expect(
      () => _loan(amount: 100, repaid: 60).withRepayment(41),
      throwsArgumentError,
    );
    expect(() => _loan().withRepayment(0), throwsArgumentError);
    expect(() => _loan().withRepayment(-5), throwsArgumentError);
    expect(
      () => _loan(settled: true).withRepayment(1),
      throwsArgumentError,
      reason: 'nothing remains on a closed loan',
    );
    expect(_loan(amount: 100, repaid: 60).withRepayment(40).settled, isTrue);
  });

  test('status follows the amounts: lend 5000, get 2000 back, then 3000', () {
    var l = _loan(amount: 500000);
    expect(l.status, LoanStatus.outstanding);
    l = l.withRepayment(200000);
    expect(l.status, LoanStatus.partiallyRepaid);
    expect(l.repaidMinor, 200000);
    expect(l.remainingMinor, 300000);
    l = l.withRepayment(300000);
    expect(l.status, LoanStatus.fullyRepaid);
    expect(l.remainingMinor, 0);

    final borrowed = _loan(
      direction: LoanDirection.borrowed,
      amount: 1000,
    ).withRepayment(400);
    expect(borrowed.status, LoanStatus.partiallyRepaid);
    expect(borrowed.outstandingMinor, 600);

    final cancelled = _loan(repaid: 100, settled: true, cancelled: true);
    expect(cancelled.status, LoanStatus.cancelled);
    expect(cancelled.outstandingMinor, 0);
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

  test('totals separate original amounts from what was paid back', () {
    final t = LoanTotals.of(
      [
        _loan(id: 'a', amount: 500000, repaid: 200000),
        _loan(id: 'b', amount: 10000, repaid: 10000, settled: true),
        _loan(
          id: 'c',
          direction: LoanDirection.borrowed,
          amount: 30000,
          repaid: 5000,
        ),
        _loan(id: 'x', amount: 77777, settled: true, cancelled: true),
        _loan(id: 'usd', amount: 70000, repaid: 1000, currency: 'USD'),
      ],
      'INR',
      today,
    );
    expect(t.lentMinor, 510000, reason: 'cancelled and USD excluded');
    expect(t.returnedToMeMinor, 210000);
    expect(t.toReceiveMinor, 300000);
    expect(t.borrowedMinor, 30000);
    expect(t.repaidByMeMinor, 5000);
    expect(t.toPayMinor, 25000);

    final usd = LoanTotals.of(
      [_loan(id: 'usd', currency: 'USD')],
      'USD',
      today,
    );
    expect(usd.lentMinor, 100000, reason: 'each currency is totalled alone');
  });
}
