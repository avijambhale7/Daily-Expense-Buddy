import 'package:daily/core/dates/local_date.dart';
import 'package:daily/core/dates/report_period.dart';
import 'package:daily/domain/models/daily_status.dart';
import 'package:daily/domain/models/expense.dart';
import 'package:daily/domain/models/report_summary.dart';
import 'package:daily/domain/services/report_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

var _id = 0;
Expense e(
  String date,
  int amount, {
  String cat = 'food',
  String currency = 'INR',
}) => Expense(
  id: 'e${_id++}',
  amountMinor: amount,
  currencyCode: currency,
  categoryId: cat,
  date: LocalDate.parse(date),
);

void main() {
  final today = LocalDate(2025, 10, 14); // Tuesday

  group('monthly report (past month)', () {
    final period = ReportPeriod.of(
      ReportPeriodType.month,
      LocalDate(2025, 9, 1),
    );
    final expenses = [
      e('2025-09-01', 10000),
      e('2025-09-01', 5000, cat: 'transport'),
      e('2025-09-15', 30000, cat: 'bills'),
      e('2025-09-30', 2000),
      e('2025-09-30', 99999, currency: 'USD'), // other currency – excluded
      e('2025-10-01', 70000), // outside the period
      e('2025-08-31', 40000), // previous period
      e('2025-08-10', 10000), // previous period
    ];
    final s = ReportCalculator.summarize(
      period: period,
      expenses: expenses,
      currencyCode: 'INR',
      today: today,
    );

    test('total and counts include only qualifying expenses', () {
      expect(s.totalMinor, 47000);
      expect(s.transactionCount, 4);
      expect(s.excludedOtherCurrencyCount, 1);
    });

    test('averages', () {
      expect(s.elapsedDays, 30);
      expect(s.spendingDays, 3);
      expect(s.noSpendDays, 27);
      expect(s.avgPerCalendarDayMinor, 1567); // 47000 / 30 = 1566.67
      expect(s.avgPerSpendingDayMinor, 15667); // 47000 / 3 = 15666.67
    });

    test('highest and lowest (non-zero) days', () {
      expect(s.highestDay, DayTotal(LocalDate(2025, 9, 15), 30000));
      expect(s.lowestDay, DayTotal(LocalDate(2025, 9, 30), 2000));
    });

    test('daily totals cover every day of the month', () {
      expect(s.dailyTotals.length, 30);
      expect(s.dailyTotals.first, DayTotal(LocalDate(2025, 9, 1), 15000));
      expect(s.dailyTotals.where((d) => d.totalMinor == 0).length, 27);
    });

    test('category totals and shares', () {
      expect(s.categories.map((c) => c.categoryId), [
        'bills',
        'food',
        'transport',
      ]);
      expect(s.categories.first.totalMinor, 30000);
      expect(s.categories.first.shareBasisPoints, 6383); // 30000/47000
      expect(
        s.categories.fold<int>(0, (a, c) => a + c.totalMinor),
        s.totalMinor,
      );
    });

    test('comparison with the previous calendar month', () {
      final c = s.comparison!;
      expect(c.previousPeriod.range.start, LocalDate(2025, 8, 1));
      expect(c.previousTotalMinor, 50000);
      expect(c.differenceMinor, -3000);
      expect(c.changeBasisPoints, -600);
    });
  });

  test('current period averages use elapsed days only', () {
    final period = ReportPeriod.of(ReportPeriodType.month, today);
    final s = ReportCalculator.summarize(
      period: period,
      expenses: [e('2025-10-01', 1400), e('2025-10-14', 1400)],
      currencyCode: 'INR',
      today: today,
    );
    expect(s.elapsedDays, 14);
    expect(s.avgPerCalendarDayMinor, 200);
    expect(s.dailyTotals.length, 31);
  });

  test('empty period produces no averages and no division by zero', () {
    final s = ReportCalculator.summarize(
      period: ReportPeriod.of(ReportPeriodType.week, LocalDate(2025, 9, 10)),
      expenses: const [],
      currencyCode: 'INR',
      today: today,
    );
    expect(s.isEmpty, isTrue);
    expect(s.totalMinor, 0);
    expect(s.avgPerSpendingDayMinor, isNull);
    expect(s.avgPerCalendarDayMinor, 0);
    expect(s.highestDay, isNull);
    expect(s.lowestDay, isNull);
    expect(s.comparison!.changeBasisPoints, isNull);
  });

  test('previous zero period yields no percentage', () {
    final s = ReportCalculator.summarize(
      period: ReportPeriod.of(ReportPeriodType.day, LocalDate(2025, 10, 10)),
      expenses: [e('2025-10-10', 500)],
      currencyCode: 'INR',
      today: today,
    );
    expect(s.comparison!.previousTotalMinor, 0);
    expect(s.comparison!.changeBasisPoints, isNull);
    expect(s.lowestDay, isNull, reason: 'needs two spending days');
  });

  test('future period has no elapsed days', () {
    final s = ReportCalculator.summarize(
      period: ReportPeriod.of(ReportPeriodType.month, LocalDate(2025, 12, 1)),
      expenses: const [],
      currencyCode: 'INR',
      today: today,
    );
    expect(s.elapsedDays, 0);
    expect(s.avgPerCalendarDayMinor, isNull);
  });

  test('weekly report respects week start', () {
    final expenses = [
      e('2025-10-12', 100),
      e('2025-10-13', 200),
      e('2025-10-18', 300),
    ];
    final sunday = ReportCalculator.summarize(
      period: ReportPeriod.of(
        ReportPeriodType.week,
        today,
        weekStart: DateTime.sunday,
      ),
      expenses: expenses,
      currencyCode: 'INR',
      today: LocalDate(2025, 10, 18),
    );
    expect(sunday.totalMinor, 600);
    final monday = ReportCalculator.summarize(
      period: ReportPeriod.of(
        ReportPeriodType.week,
        today,
        weekStart: DateTime.monday,
      ),
      expenses: expenses,
      currencyCode: 'INR',
      today: LocalDate(2025, 10, 19),
    );
    expect(monday.totalMinor, 500);
  });

  test(
    'yearly report: monthly totals, highest/lowest month, monthly average',
    () {
      final s = ReportCalculator.summarize(
        period: ReportPeriod.of(ReportPeriodType.year, LocalDate(2024, 1, 1)),
        expenses: [
          e('2024-01-05', 1000),
          e('2024-02-29', 5000),
          e('2024-07-01', 300),
          e('2023-12-31', 9999),
        ],
        currencyCode: 'INR',
        today: today,
      );
      expect(s.monthlyTotals.length, 12);
      expect(s.monthlyTotals[1].totalMinor, 5000);
      expect(s.highestMonth!.month, 2);
      expect(s.lowestMonth!.month, 7);
      expect(s.avgPerMonthMinor, 525); // 6300 / 12
      expect(s.elapsedDays, 366);
      expect(s.comparison!.previousTotalMinor, 9999);
    },
  );

  test('weekly buckets inside a month', () {
    final daily = [
      for (final d in DateRange(
        LocalDate(2025, 10, 1),
        LocalDate(2025, 10, 14),
      ).days)
        DayTotal(d, 100),
    ];
    final weeks = ReportCalculator.weeklyBuckets(daily, DateTime.monday);
    expect(weeks.map((w) => w.date), [
      LocalDate(2025, 10, 1),
      LocalDate(2025, 10, 6),
      LocalDate(2025, 10, 13),
    ]);
    expect(weeks.map((w) => w.totalMinor), [500, 700, 200]);
  });

  group('dashboard', () {
    final expenses = [
      e('2025-10-14', 1000),
      e('2025-10-14', 500, cat: 'transport'),
      e('2025-10-13', 2000),
      e('2025-10-02', 4000),
      e('2025-03-01', 8000),
      e('2025-10-14', 7777, currency: 'EUR'),
    ];
    final d = ReportCalculator.dashboard(
      expenses: expenses,
      currencyCode: 'INR',
      today: today,
      weekStart: DateTime.monday,
      statuses: {
        LocalDate(2025, 10, 12): StoredDayStatus.noExpenses,
        LocalDate(2025, 10, 11): StoredDayStatus.completed,
      },
      accountStart: LocalDate(2025, 10, 9),
    );

    test('totals per period', () {
      expect(d.todayTotalMinor, 1500);
      expect(d.todayCount, 2);
      expect(d.weekTotalMinor, 3500);
      expect(d.monthTotalMinor, 7500);
      expect(d.yearTotalMinor, 15500);
      expect(d.excludedOtherCurrencyCount, 1);
      expect(d.weekDaily.length, 7);
      expect(d.trend.length, 6);
      expect(d.trend.last.totalMinor, 7500);
    });

    test('tracking states and incomplete days since account start', () {
      expect(d.todayState, DailyTrackingState.notReviewed);
      expect(d.yesterdayState, DailyTrackingState.notReviewed);
      // 13 (yesterday), 10 and 9 not reviewed; 11, 12 reviewed; 8 predates account.
      expect(d.incompleteDays, [
        LocalDate(2025, 10, 13),
        LocalDate(2025, 10, 10),
        LocalDate(2025, 10, 9),
      ]);
    });

    test('recent expenses newest first', () {
      expect(d.recent.first.date, today);
      expect(d.recent.length, 5);
    });

    test('dashboard range covers week, year and six months', () {
      final r = ReportCalculator.dashboardRange(
        LocalDate(2025, 1, 2),
        DateTime.monday,
      );
      expect(r.start, LocalDate(2024, 8, 1));
      expect(r.end, LocalDate(2025, 1, 2));
    });
  });
}
