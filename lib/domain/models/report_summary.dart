import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';
import '../../core/dates/report_period.dart';
import 'daily_status.dart';
import 'expense.dart';

class DayTotal extends Equatable {
  const DayTotal(this.date, this.totalMinor);
  final LocalDate date;
  final int totalMinor;
  @override
  List<Object?> get props => [date, totalMinor];
}

class MonthTotal extends Equatable {
  const MonthTotal(this.year, this.month, this.totalMinor);
  final int year;
  final int month;
  final int totalMinor;
  LocalDate get firstDay => LocalDate(year, month, 1);
  @override
  List<Object?> get props => [year, month, totalMinor];
}

class CategoryTotal extends Equatable {
  const CategoryTotal({
    required this.categoryId,
    required this.totalMinor,
    required this.count,
    required this.shareBasisPoints,
  });
  final String categoryId;
  final int totalMinor;
  final int count;

  /// Share of the period total, in basis points (10000 = 100%).
  final int shareBasisPoints;
  @override
  List<Object?> get props => [categoryId, totalMinor, count, shareBasisPoints];
}

/// Comparison against the equivalent previous period.
class PeriodComparison extends Equatable {
  const PeriodComparison({
    required this.previousPeriod,
    required this.previousTotalMinor,
    required this.differenceMinor,
    required this.changeBasisPoints,
  });

  final ReportPeriod previousPeriod;
  final int previousTotalMinor;
  final int differenceMinor;

  /// Null when the previous period total is zero (a percentage would be
  /// infinite/undefined and is therefore not shown).
  final int? changeBasisPoints;

  @override
  List<Object?> get props => [
    previousPeriod,
    previousTotalMinor,
    differenceMinor,
    changeBasisPoints,
  ];
}

/// Fully computed report for one [ReportPeriod]. Every number here is derived
/// from expense records by `ReportCalculator`; nothing is stored or
/// hard-coded.
class ReportSummary extends Equatable {
  const ReportSummary({
    required this.period,
    required this.currencyCode,
    required this.totalMinor,
    required this.transactionCount,
    required this.elapsedDays,
    required this.spendingDays,
    required this.noSpendDays,
    required this.avgPerCalendarDayMinor,
    required this.avgPerSpendingDayMinor,
    required this.highestDay,
    required this.lowestDay,
    required this.dailyTotals,
    required this.monthlyTotals,
    required this.highestMonth,
    required this.lowestMonth,
    required this.avgPerMonthMinor,
    required this.categories,
    required this.comparison,
    required this.excludedOtherCurrencyCount,
    required this.expenses,
  });

  final ReportPeriod period;
  final String currencyCode;
  final int totalMinor;
  final int transactionCount;

  /// Calendar days of the period up to and including today (all days for
  /// past periods). This is the divisor for [avgPerCalendarDayMinor].
  final int elapsedDays;

  /// Distinct days with at least one qualifying expense.
  final int spendingDays;

  /// Elapsed days with no recorded expenses.
  final int noSpendDays;

  final int? avgPerCalendarDayMinor;
  final int? avgPerSpendingDayMinor;

  /// Day with the highest total; null when nothing was spent.
  final DayTotal? highestDay;

  /// Lowest **non-zero** spending day. Days without expenses are excluded
  /// (they are reported separately as [noSpendDays]). Null when fewer than
  /// two spending days exist.
  final DayTotal? lowestDay;

  /// One entry per day of the period (zero-filled).
  final List<DayTotal> dailyTotals;

  /// One entry per calendar month touched by the period.
  final List<MonthTotal> monthlyTotals;
  final MonthTotal? highestMonth;

  /// Lowest non-zero month among elapsed months.
  final MonthTotal? lowestMonth;

  /// Total divided by elapsed months (yearly reports).
  final int? avgPerMonthMinor;

  /// Sorted by total, descending.
  final List<CategoryTotal> categories;
  final PeriodComparison? comparison;

  /// Expenses in the period recorded in a different currency; they are not
  /// included in any total (no exchange-rate conversion is performed).
  final int excludedOtherCurrencyCount;

  /// Qualifying expenses, newest first.
  final List<Expense> expenses;

  bool get isEmpty => transactionCount == 0;

  @override
  List<Object?> get props => [
    period,
    currencyCode,
    totalMinor,
    transactionCount,
    elapsedDays,
    spendingDays,
    noSpendDays,
    avgPerCalendarDayMinor,
    avgPerSpendingDayMinor,
    highestDay,
    lowestDay,
    dailyTotals,
    monthlyTotals,
    highestMonth,
    lowestMonth,
    avgPerMonthMinor,
    categories,
    comparison,
    excludedOtherCurrencyCount,
    expenses,
  ];
}

/// Everything the home dashboard shows.
class DashboardSummary extends Equatable {
  const DashboardSummary({
    required this.today,
    required this.currencyCode,
    required this.todayTotalMinor,
    required this.todayCount,
    required this.weekTotalMinor,
    required this.monthTotalMinor,
    required this.yearTotalMinor,
    required this.weekDaily,
    required this.monthCategories,
    required this.recent,
    required this.trend,
    required this.todayState,
    required this.yesterdayState,
    required this.incompleteDays,
    required this.excludedOtherCurrencyCount,
    required this.weekReviewedDays,
    required this.weekElapsedDays,
    this.dailyAllowanceMinor,
    this.monthBudgetMinor,
  });

  final LocalDate today;
  final String currencyCode;
  final int todayTotalMinor;
  final int todayCount;
  final int weekTotalMinor;
  final int monthTotalMinor;
  final int yearTotalMinor;

  /// The current week, one entry per day.
  final List<DayTotal> weekDaily;
  final List<CategoryTotal> monthCategories;
  final List<Expense> recent;

  /// The last six calendar months, oldest first.
  final List<MonthTotal> trend;
  final DailyTrackingState todayState;

  /// Null when yesterday predates the account.
  final DailyTrackingState? yesterdayState;

  /// Past days (last 7, excluding today) that were not reviewed.
  final List<LocalDate> incompleteDays;
  final int excludedOtherCurrencyCount;

  /// Days of the current week (up to today) the user has reviewed.
  final int weekReviewedDays;

  /// Days of the current week up to and including today.
  final int weekElapsedDays;

  /// What can still be spent today while staying within the overall monthly
  /// budget; null when no overall budget is set.
  final int? dailyAllowanceMinor;

  /// The overall monthly budget, if set and in the reporting currency.
  final int? monthBudgetMinor;

  bool get hasAnyExpenses => yearTotalMinor > 0 || recent.isNotEmpty;

  @override
  List<Object?> get props => [
    today,
    currencyCode,
    todayTotalMinor,
    todayCount,
    weekTotalMinor,
    monthTotalMinor,
    yearTotalMinor,
    weekDaily,
    monthCategories,
    recent,
    trend,
    todayState,
    yesterdayState,
    incompleteDays,
    excludedOtherCurrencyCount,
    weekReviewedDays,
    weekElapsedDays,
    dailyAllowanceMinor,
    monthBudgetMinor,
  ];
}
