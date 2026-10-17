import 'package:daily/core/dates/local_date.dart';
import 'package:daily/domain/models/loan.dart';
import 'package:daily/domain/models/user_preferences.dart';
import 'package:daily/domain/services/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

Loan _loan(
  String id, {
  LocalDate? due,
  bool settled = false,
  LoanDirection direction = LoanDirection.lent,
}) => Loan(
  id: id,
  direction: direction,
  personName: 'Rahul',
  amountMinor: 1000,
  currencyCode: 'INR',
  date: LocalDate(2025, 10, 1),
  dueDate: due,
  settled: settled,
);

void main() {
  // Tuesday 14 Oct 2025, 18:30; reminders at 21:00.
  final now = DateTime(2025, 10, 14, 18, 30);
  const settings = ReminderSettings(enabled: true, timeMinutes: 21 * 60);

  List<PlannedReminder> plan(Iterable<Loan> loans, {ReminderSettings? s}) =>
      ReminderPlanner.planLoanDue(
        now: now,
        settings: s ?? settings,
        loans: loans,
      );

  test('one reminder on the due date at the reminder time', () {
    final r = plan([_loan('a', due: LocalDate(2025, 10, 20))]).single;
    expect(r.at, DateTime(2025, 10, 20, 21));
    expect(r.payload, '/loans');
    expect(r.body, contains('Rahul'));
    expect(r.id, ReminderPlanner.loanIdFor('a'));
  });

  test('wording matches the direction', () {
    final lent = plan([_loan('a', due: LocalDate(2025, 10, 20))]).single;
    final borrowed = plan([
      _loan(
        'b',
        due: LocalDate(2025, 10, 20),
        direction: LoanDirection.borrowed,
      ),
    ]).single;
    expect(lent.title, 'A loan is due back today');
    expect(borrowed.title, 'A repayment is due today');
  });

  test('no reminder without a due date, once closed, or after it fired', () {
    expect(plan([_loan('a')]), isEmpty);
    expect(
      plan([_loan('a', due: LocalDate(2025, 10, 20), settled: true)]),
      isEmpty,
    );
    // Due today at 21:00 is still ahead; due yesterday has already fired.
    expect(plan([_loan('a', due: LocalDate(2025, 10, 14))]), hasLength(1));
    expect(plan([_loan('a', due: LocalDate(2025, 10, 13))]), isEmpty);
  });

  test('turning reminders off disables loan reminders too', () {
    expect(
      plan([
        _loan('a', due: LocalDate(2025, 10, 20)),
      ], s: const ReminderSettings()),
      isEmpty,
    );
  });

  test('only due dates inside the planning horizon are scheduled', () {
    final far = LocalDate(2025, 10, 14).addDays(ReminderPlanner.horizonDays);
    expect(plan([_loan('a', due: far)]), isEmpty);
  });

  test('ids are stable, in their own range, and differ per loan', () {
    final a = ReminderPlanner.loanIdFor('loan-a');
    expect(ReminderPlanner.loanIdFor('loan-a'), a);
    expect(ReminderPlanner.loanIdFor('loan-b'), isNot(a));
    expect(a, greaterThanOrEqualTo(ReminderPlanner.loanIdBase));
    expect(a, lessThan(ReminderPlanner.loanIdBase + 100000));
  });
}
