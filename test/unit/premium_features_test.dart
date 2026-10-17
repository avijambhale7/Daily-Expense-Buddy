import 'package:daily/core/dates/local_date.dart';
import 'package:daily/domain/models/expense.dart';
import 'package:daily/domain/models/recurring_expense.dart';
import 'package:daily/domain/models/savings_goal.dart';
import 'package:daily/domain/services/advanced_report.dart';
import 'package:daily/services/app_lock/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecurringExpense _rec(
  RecurrenceFrequency f,
  LocalDate start, {
  LocalDate? last,
  bool active = true,
}) => RecurringExpense(
  id: 'r1',
  amountMinor: 100000,
  currencyCode: 'INR',
  categoryId: 'accommodation',
  frequency: f,
  startDate: start,
  lastPostedDate: last,
  active: active,
);

Expense _e(
  String date,
  int amount, {
  String cat = 'food',
  String cur = 'INR',
}) => Expense(
  id: '$date-$amount-$cat',
  amountMinor: amount,
  currencyCode: cur,
  categoryId: cat,
  date: LocalDate.parse(date),
);

void main() {
  group('Recurring expenses', () {
    test('monthly on the 31st falls back to the last day of short months', () {
      final r = _rec(RecurrenceFrequency.monthly, LocalDate(2026, 1, 31));
      expect(r.dueDates(LocalDate(2026, 4, 30)).map((d) => d.toIso()), [
        '2026-01-31',
        '2026-02-28',
        '2026-03-31',
        '2026-04-30',
      ]);
    });

    test('yearly on 29 Feb uses 28 Feb in other years', () {
      final r = _rec(RecurrenceFrequency.yearly, LocalDate(2024, 2, 29));
      expect(r.occurrence(1), LocalDate(2025, 2, 28));
      expect(r.occurrence(4), LocalDate(2028, 2, 29));
    });

    test('only dates after the last posted one are due', () {
      final r = _rec(
        RecurrenceFrequency.weekly,
        LocalDate(2026, 10, 1),
        last: LocalDate(2026, 10, 8),
      );
      expect(r.dueDates(LocalDate(2026, 10, 22)).map((d) => d.toIso()), [
        '2026-10-15',
        '2026-10-22',
      ]);
      expect(r.nextDate(LocalDate(2026, 10, 23)), LocalDate(2026, 10, 29));
    });

    test(
      'nothing is due in the future, when paused, and catch-up is capped',
      () {
        final today = LocalDate(2026, 10, 17);
        expect(
          _rec(
            RecurrenceFrequency.monthly,
            LocalDate(2026, 11, 1),
          ).dueDates(today),
          isEmpty,
        );
        expect(
          _rec(
            RecurrenceFrequency.monthly,
            LocalDate(2026, 1, 1),
            active: false,
          ).dueDates(today),
          isEmpty,
        );
        final weekly = _rec(RecurrenceFrequency.weekly, LocalDate(2020, 1, 1));
        final due = weekly.dueDates(today);
        expect(due, hasLength(RecurringExpense.maxCatchUp));
        expect(due.last <= today, isTrue);
      },
    );

    test('each occurrence has a stable expense id', () {
      final r = _rec(RecurrenceFrequency.monthly, LocalDate(2026, 10, 1));
      final e = r.expenseFor(LocalDate(2026, 10, 1));
      expect(e.id, 'rec_r1_2026-10-01');
      expect(e.amountMinor, 100000);
      expect(e.categoryId, 'accommodation');
    });
  });

  group('Savings goals', () {
    const goal = SavingsGoal(
      id: 'g',
      name: 'Trip',
      targetMinor: 1000000,
      currencyCode: 'INR',
    );

    test('progress, remaining and never below zero', () {
      final g = goal.withChange(250000);
      expect(g.progress, 0.25);
      expect(g.remainingMinor, 750000);
      expect(g.withChange(-999999999).savedMinor, 0);
      expect(g.withChange(800000).reached, isTrue);
    });

    test('amount per day rounds up to reach the target on time', () {
      final g = goal.copyWith(targetDate: () => LocalDate(2026, 10, 20));
      // 4 days left including today: 10,00,000 / 4 = 2,50,000.
      expect(g.perDayMinor(LocalDate(2026, 10, 17)), 250000);
      expect(
        goal
            .copyWith(targetDate: () => LocalDate(2026, 10, 19))
            .perDayMinor(LocalDate(2026, 10, 17)),
        333334,
      );
      expect(goal.perDayMinor(LocalDate(2026, 10, 17)), isNull);
      expect(g.perDayMinor(LocalDate(2026, 10, 21)), isNull, reason: 'past');
    });
  });

  group('Advanced report', () {
    final today = LocalDate(2026, 10, 17);

    test('12-month trend ending this month, other currencies excluded', () {
      final r = AdvancedReport.of(
        today: today,
        currencyCode: 'INR',
        expenses: [
          _e('2026-10-02', 500),
          _e('2026-10-10', 700),
          _e('2026-09-15', 300),
          _e('2025-11-01', 100),
          _e('2025-10-31', 9999, cur: 'INR'), // outside the 12 months
          _e('2026-10-03', 5000, cur: 'USD'),
        ],
      );
      expect(r.months, hasLength(12));
      expect(r.months.first.month, LocalDate(2025, 11, 1));
      expect(r.months.first.totalMinor, 100);
      expect(r.months.last.totalMinor, 1200);
      expect(r.busiestMonth!.month, LocalDate(2026, 10, 1));
      expect(r.averageMonthMinor, 200, reason: '(100 + 300) / 2 past months');
    });

    test('category changes compare this month with last month', () {
      final r = AdvancedReport.of(
        today: today,
        currencyCode: 'INR',
        expenses: [
          _e('2026-10-01', 1500),
          _e('2026-09-01', 1000),
          _e('2026-10-02', 400, cat: 'travel'),
          _e('2026-09-05', 800, cat: 'shopping'),
        ],
      );
      final food = r.categoryChanges.firstWhere((c) => c.categoryId == 'food');
      expect(food.percent, 50);
      final travel = r.categoryChanges.firstWhere(
        (c) => c.categoryId == 'travel',
      );
      expect(travel.percent, isNull, reason: 'new this month');
      final shopping = r.categoryChanges.firstWhere(
        (c) => c.categoryId == 'shopping',
      );
      expect(shopping.percent, -100);
      expect(r.categoryChanges.first.categoryId, 'food');
    });

    test('weekday averages count days without spending as zero', () {
      // 2026-10-17 is a Saturday; the 84-day window holds 12 of each day.
      final r = AdvancedReport.of(
        today: today,
        currencyCode: 'INR',
        expenses: [_e('2026-10-17', 1200), _e('2026-10-10', 1200)],
      );
      expect(r.weekdayAverages[5], 200, reason: '2400 / 12 Saturdays');
      expect(r.busiestWeekday, 5);
      expect(r.weekdayAverages[0], 0);
    });
  });

  group('App lock', () {
    late SharedPreferencesAppLockStore store;
    var clock = DateTime(2026, 10, 17, 9);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = SharedPreferencesAppLockStore(
        await SharedPreferences.getInstance(),
      );
      clock = DateTime(2026, 10, 17, 9);
    });

    test('only a salted hash is stored and the PIN verifies', () async {
      await store.setPin('2580');
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getKeys().map(prefs.get).join(' ');
      expect(saved.contains('2580'), isFalse);
      expect(store.verify('2580'), isTrue);
      expect(store.verify('0000'), isFalse);
      await store.clear();
      expect(store.enabled, isFalse);
    });

    test('locks at start and again after a minute in the background', () async {
      await store.setPin('1234');
      final c = AppLockController(store, now: () => clock);
      expect(c.locked, isTrue);
      expect(c.unlockWithPin('9999'), isFalse);
      expect(c.unlockWithPin('1234'), isTrue);
      expect(c.locked, isFalse);

      c.paused();
      clock = clock.add(const Duration(seconds: 30));
      c.resumed();
      expect(c.locked, isFalse, reason: 'a quick switch does not lock');

      c.paused();
      clock = clock.add(const Duration(minutes: 2));
      c.resumed();
      expect(c.locked, isTrue);
    });

    test('without a PIN the app is never locked', () {
      final c = AppLockController(store, now: () => clock);
      expect(c.locked, isFalse);
    });
  });
}
