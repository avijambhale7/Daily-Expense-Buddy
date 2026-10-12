import '../../core/dates/local_date.dart';
import '../../core/dates/report_period.dart';
import '../../core/money/money_math.dart';
import '../models/budget.dart';
import '../models/daily_status.dart';
import '../models/expense.dart';
import '../models/report_summary.dart';
import 'budget_calculator.dart';
import 'tracking_status_service.dart';

/// All financial aggregation in the app goes through this class so every
/// screen uses identical definitions.
///
/// Definitions
/// * **Qualifying expense** – positive amount, recorded in the reporting
///   currency, dated inside the period. Other currencies are counted in
///   `excludedOtherCurrencyCount` and never summed (no FX conversion).
/// * **Total** – integer sum of qualifying amounts (minor units).
/// * **Average per calendar day** – total ÷ elapsed calendar days of the
///   period (every day of a past period; days up to today for the current
///   period; future days are not counted). Rounded half away from zero.
/// * **Average per spending day** – total ÷ distinct days with qualifying
///   expenses. Null when there are none (no division by zero).
/// * **Highest day** – day with the largest total.
/// * **Lowest day** – smallest **non-zero** day total; zero days are
///   reported as "no-spend days" instead. Requires ≥ 2 spending days.
/// * **Comparison** – against the equivalent previous period (previous
///   day/week/calendar month/calendar year or same-length custom range).
///   The percentage is null when the previous total is zero.
abstract final class ReportCalculator {
  static bool _qualifies(Expense e, String currency, DateRange range) =>
      e.currencyCode == currency && e.amountMinor > 0 && range.contains(e.date);

  static int totalFor(
    Iterable<Expense> expenses,
    String currency,
    DateRange range,
  ) {
    var total = 0;
    for (final e in expenses) {
      if (_qualifies(e, currency, range)) total += e.amountMinor;
    }
    return total;
  }

  static Map<LocalDate, int> dailyTotalsMap(
    Iterable<Expense> expenses,
    String currency,
    DateRange range,
  ) {
    final map = <LocalDate, int>{};
    for (final e in expenses) {
      if (_qualifies(e, currency, range)) {
        map[e.date] = (map[e.date] ?? 0) + e.amountMinor;
      }
    }
    return map;
  }

  static List<CategoryTotal> categoryTotals(
    Iterable<Expense> expenses,
    String currency,
    DateRange range,
  ) {
    final totals = <String, int>{};
    final counts = <String, int>{};
    var grand = 0;
    for (final e in expenses) {
      if (!_qualifies(e, currency, range)) continue;
      totals[e.categoryId] = (totals[e.categoryId] ?? 0) + e.amountMinor;
      counts[e.categoryId] = (counts[e.categoryId] ?? 0) + 1;
      grand += e.amountMinor;
    }
    final list =
        [
          for (final entry in totals.entries)
            CategoryTotal(
              categoryId: entry.key,
              totalMinor: entry.value,
              count: counts[entry.key]!,
              shareBasisPoints:
                  MoneyMath.shareBasisPoints(entry.value, grand) ?? 0,
            ),
        ]..sort((a, b) {
          final c = b.totalMinor.compareTo(a.totalMinor);
          return c != 0 ? c : a.categoryId.compareTo(b.categoryId);
        });
    return list;
  }

  static List<MonthTotal> monthlyTotals(
    Iterable<Expense> expenses,
    String currency,
    DateRange range,
  ) {
    final map = <String, int>{};
    for (final e in expenses) {
      if (_qualifies(e, currency, range)) {
        map[e.date.monthKey] = (map[e.date.monthKey] ?? 0) + e.amountMinor;
      }
    }
    final result = <MonthTotal>[];
    var m = range.start.startOfMonth;
    while (m <= range.end) {
      result.add(MonthTotal(m.year, m.month, map[m.monthKey] ?? 0));
      m = m.addMonths(1);
    }
    return result;
  }

  static ReportSummary summarize({
    required ReportPeriod period,
    required Iterable<Expense> expenses,
    required String currencyCode,
    required LocalDate today,
    bool includeComparison = true,
  }) {
    final range = period.range;
    final all = expenses.toList(growable: false);

    final inPeriod = <Expense>[];
    var excluded = 0;
    for (final e in all) {
      if (!range.contains(e.date) || e.amountMinor <= 0) continue;
      if (e.currencyCode == currencyCode) {
        inPeriod.add(e);
      } else {
        excluded++;
      }
    }
    inPeriod.sort(Expense.newestFirst);

    final total = MoneyMath.sum(inPeriod.map((e) => e.amountMinor));
    final dailyMap = dailyTotalsMap(inPeriod, currencyCode, range);
    final dailyTotals = [
      for (final d in range.days) DayTotal(d, dailyMap[d] ?? 0),
    ];

    final elapsedRange = range.start > today
        ? null
        : DateRange(range.start, LocalDate.min(range.end, today));
    final elapsedDays = elapsedRange?.dayCount ?? 0;
    final spendingDays = dailyMap.length;
    final elapsedSpendingDays = elapsedRange == null
        ? 0
        : dailyMap.keys.where(elapsedRange.contains).length;

    DayTotal? highest;
    DayTotal? lowest;
    for (final entry in dailyMap.entries) {
      final dt = DayTotal(entry.key, entry.value);
      if (highest == null ||
          dt.totalMinor > highest.totalMinor ||
          (dt.totalMinor == highest.totalMinor && dt.date < highest.date)) {
        highest = dt;
      }
      if (lowest == null ||
          dt.totalMinor < lowest.totalMinor ||
          (dt.totalMinor == lowest.totalMinor && dt.date < lowest.date)) {
        lowest = dt;
      }
    }
    if (spendingDays < 2) lowest = null;

    final months = monthlyTotals(inPeriod, currencyCode, range);
    MonthTotal? highestMonth;
    MonthTotal? lowestMonth;
    var elapsedMonths = 0;
    for (final m in months) {
      if (m.firstDay > today) continue;
      elapsedMonths++;
      if (m.totalMinor <= 0) continue;
      if (highestMonth == null || m.totalMinor > highestMonth.totalMinor) {
        highestMonth = m;
      }
      if (lowestMonth == null || m.totalMinor < lowestMonth.totalMinor) {
        lowestMonth = m;
      }
    }
    final spendingMonths = months.where((m) => m.totalMinor > 0).length;
    if (spendingMonths < 2) lowestMonth = null;

    PeriodComparison? comparison;
    if (includeComparison) {
      final prev = period.previous;
      final prevTotal = totalFor(all, currencyCode, prev.range);
      comparison = PeriodComparison(
        previousPeriod: prev,
        previousTotalMinor: prevTotal,
        differenceMinor: total - prevTotal,
        changeBasisPoints: MoneyMath.changeBasisPoints(
          current: total,
          previous: prevTotal,
        ),
      );
    }

    return ReportSummary(
      period: period,
      currencyCode: currencyCode,
      totalMinor: total,
      transactionCount: inPeriod.length,
      elapsedDays: elapsedDays,
      spendingDays: spendingDays,
      noSpendDays: elapsedDays - elapsedSpendingDays,
      avgPerCalendarDayMinor: elapsedDays > 0
          ? MoneyMath.divideRounded(total, elapsedDays)
          : null,
      avgPerSpendingDayMinor: spendingDays > 0
          ? MoneyMath.divideRounded(total, spendingDays)
          : null,
      highestDay: highest,
      lowestDay: lowest,
      dailyTotals: dailyTotals,
      monthlyTotals: months,
      highestMonth: highestMonth,
      lowestMonth: lowestMonth,
      avgPerMonthMinor: elapsedMonths > 0
          ? MoneyMath.divideRounded(total, elapsedMonths)
          : null,
      categories: categoryTotals(inPeriod, currencyCode, range),
      comparison: comparison,
      excludedOtherCurrencyCount: excluded,
      expenses: inPeriod,
    );
  }

  /// Groups daily totals into weeks starting on [weekStart]. Each bucket is
  /// keyed by the first day of the week that falls inside the input.
  static List<DayTotal> weeklyBuckets(List<DayTotal> daily, int weekStart) {
    final buckets = <LocalDate, int>{};
    final order = <LocalDate>[];
    for (final d in daily) {
      final key = LocalDate.max(
        d.date.startOfWeek(weekStart),
        daily.first.date,
      );
      if (!buckets.containsKey(key)) order.add(key);
      buckets[key] = (buckets[key] ?? 0) + d.totalMinor;
    }
    return [for (final k in order) DayTotal(k, buckets[k]!)];
  }

  /// The date range the dashboard needs: covers the current week, month,
  /// year and the last six months.
  static DateRange dashboardRange(LocalDate today, int weekStart) {
    final starts = [
      today.startOfWeek(weekStart),
      today.startOfYear,
      today.startOfMonth.addMonths(-5),
    ]..sort();
    return DateRange(starts.first, today);
  }

  static DashboardSummary dashboard({
    required Iterable<Expense> expenses,
    required String currencyCode,
    required LocalDate today,
    required int weekStart,
    required Map<LocalDate, StoredDayStatus> statuses,
    LocalDate? accountStart,
    Budget? overallBudget,
    int recentCount = 6,
  }) {
    final list = expenses.toList(growable: false);
    final weekStartDate = today.startOfWeek(weekStart);
    final weekRange = DateRange(weekStartDate, weekStartDate.addDays(6));
    final monthRange = DateRange(today.startOfMonth, today.endOfMonth);
    final yearRange = DateRange(today.startOfYear, today.endOfYear);
    final todayRange = DateRange(today, today);

    final weekMap = dailyTotalsMap(list, currencyCode, weekRange);
    final trendRange = DateRange(
      today.startOfMonth.addMonths(-5),
      today.endOfMonth,
    );

    final qualifying =
        list
            .where((e) => e.currencyCode == currencyCode && e.amountMinor > 0)
            .toList()
          ..sort(Expense.newestFirst);
    final excluded = list
        .where(
          (e) => e.currencyCode != currencyCode && monthRange.contains(e.date),
        )
        .length;

    final todayCount = qualifying.where((e) => e.date == today).length;
    final yesterday = today.addDays(-1);
    final hasExpensesOn = <LocalDate>{for (final e in list) e.date};
    final weekElapsed = DateRange(
      weekStartDate,
      today,
    ).days.where((d) => accountStart == null || d >= accountStart);
    final budget =
        overallBudget != null && overallBudget.currencyCode == currencyCode
        ? overallBudget
        : null;

    return DashboardSummary(
      today: today,
      currencyCode: currencyCode,
      todayTotalMinor: totalFor(list, currencyCode, todayRange),
      todayCount: todayCount,
      weekTotalMinor: totalFor(list, currencyCode, weekRange),
      monthTotalMinor: totalFor(list, currencyCode, monthRange),
      yearTotalMinor: totalFor(list, currencyCode, yearRange),
      weekDaily: [for (final d in weekRange.days) DayTotal(d, weekMap[d] ?? 0)],
      monthCategories: categoryTotals(list, currencyCode, monthRange),
      recent: qualifying.take(recentCount).toList(),
      trend: monthlyTotals(list, currencyCode, trendRange),
      todayState: TrackingStatusService.effectiveState(
        stored: statuses[today],
        hasExpenses: hasExpensesOn.contains(today),
      ),
      yesterdayState: accountStart != null && yesterday < accountStart
          ? null
          : TrackingStatusService.effectiveState(
              stored: statuses[yesterday],
              hasExpenses: hasExpensesOn.contains(yesterday),
            ),
      incompleteDays: TrackingStatusService.incompleteDays(
        today: today,
        stored: statuses,
        accountStart: accountStart,
      ),
      excludedOtherCurrencyCount: excluded,
      weekElapsedDays: weekElapsed.length,
      weekReviewedDays: weekElapsed.where(statuses.containsKey).length,
      monthBudgetMinor: budget?.amountMinor,
      dailyAllowanceMinor: budget == null
          ? null
          : BudgetCalculator.dailyAllowanceMinor(
              budget: budget,
              expenses: list,
              today: today,
            ),
    );
  }
}
