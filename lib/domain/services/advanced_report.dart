import '../../core/dates/local_date.dart';
import '../models/expense.dart';

/// Spending in one month.
class MonthSpend {
  const MonthSpend(this.month, this.totalMinor);

  /// First day of the month.
  final LocalDate month;
  final int totalMinor;
}

/// One category this month compared with last month.
class CategoryChange {
  const CategoryChange(
    this.categoryId,
    this.thisMonthMinor,
    this.lastMonthMinor,
  );

  final String categoryId;
  final int thisMonthMinor;
  final int lastMonthMinor;

  int get deltaMinor => thisMonthMinor - lastMonthMinor;

  /// Change in percent, or null when there was nothing last month.
  int? get percent => lastMonthMinor == 0
      ? null
      : ((deltaMinor * 100) / lastMonthMinor).round();
}

/// Premium "advanced reports": 12-month trend, category changes month on
/// month and average spending by weekday. Only expenses in the reporting
/// currency count; amounts are integer minor units throughout.
class AdvancedReport {
  const AdvancedReport({
    required this.months,
    required this.categoryChanges,
    required this.weekdayAverages,
    required this.weekdayWindowDays,
  });

  /// Range of expenses the report needs for [today].
  static DateRange rangeFor(LocalDate today) =>
      DateRange(today.startOfMonth.addMonths(-11), today);

  /// Days used for the weekday averages (ending today).
  static const weekdayWindow = 84;

  factory AdvancedReport.of({
    required List<Expense> expenses,
    required LocalDate today,
    required String currencyCode,
  }) {
    final list = [
      for (final e in expenses)
        if (e.currencyCode == currencyCode && e.date <= today) e,
    ];

    // 12-month trend, oldest first.
    final first = today.startOfMonth.addMonths(-11);
    final totals = <String, int>{};
    for (final e in list) {
      if (e.date < first) continue;
      totals.update(
        e.date.monthKey,
        (v) => v + e.amountMinor,
        ifAbsent: () => e.amountMinor,
      );
    }
    final months = [
      for (var i = 0; i < 12; i++)
        MonthSpend(
          first.addMonths(i),
          totals[first.addMonths(i).monthKey] ?? 0,
        ),
    ];

    // This month vs last month by category.
    final thisKey = today.monthKey;
    final lastKey = today.startOfMonth.addMonths(-1).monthKey;
    final thisCat = <String, int>{};
    final lastCat = <String, int>{};
    for (final e in list) {
      final key = e.date.monthKey;
      if (key == thisKey) {
        thisCat.update(
          e.categoryId,
          (v) => v + e.amountMinor,
          ifAbsent: () => e.amountMinor,
        );
      } else if (key == lastKey) {
        lastCat.update(
          e.categoryId,
          (v) => v + e.amountMinor,
          ifAbsent: () => e.amountMinor,
        );
      }
    }
    final changes =
        [
          for (final id in {...thisCat.keys, ...lastCat.keys})
            CategoryChange(id, thisCat[id] ?? 0, lastCat[id] ?? 0),
        ]..sort((a, b) {
          final byNow = b.thisMonthMinor.compareTo(a.thisMonthMinor);
          return byNow != 0
              ? byNow
              : b.lastMonthMinor.compareTo(a.lastMonthMinor);
        });

    // Average per weekday over the last [weekdayWindow] days, counting days
    // without expenses as zero so the averages are comparable.
    final start = today.addDays(-(weekdayWindow - 1));
    final sums = List<int>.filled(7, 0);
    final counts = List<int>.filled(7, 0);
    for (final d in DateRange(start, today).days) {
      counts[d.weekday - 1]++;
    }
    for (final e in list) {
      if (e.date >= start) sums[e.date.weekday - 1] += e.amountMinor;
    }
    final weekday = [
      for (var i = 0; i < 7; i++) counts[i] == 0 ? 0 : sums[i] ~/ counts[i],
    ];

    return AdvancedReport(
      months: months,
      categoryChanges: changes,
      weekdayAverages: weekday,
      weekdayWindowDays: weekdayWindow,
    );
  }

  /// Oldest first, ending with the current month.
  final List<MonthSpend> months;
  final List<CategoryChange> categoryChanges;

  /// Average spend per Monday…Sunday (index 0 = Monday).
  final List<int> weekdayAverages;
  final int weekdayWindowDays;

  /// Average of the completed months that had any spending.
  int? get averageMonthMinor {
    final done = months.take(months.length - 1).where((m) => m.totalMinor > 0);
    if (done.isEmpty) return null;
    return done.fold<int>(0, (s, m) => s + m.totalMinor) ~/ done.length;
  }

  /// The month with the highest spending (null when nothing was spent).
  MonthSpend? get busiestMonth {
    MonthSpend? best;
    for (final m in months) {
      if (m.totalMinor > 0 &&
          (best == null || m.totalMinor > best.totalMinor)) {
        best = m;
      }
    }
    return best;
  }

  /// Index (0 = Monday) of the weekday with the highest average.
  int? get busiestWeekday {
    var best = -1;
    for (var i = 0; i < 7; i++) {
      if (weekdayAverages[i] > 0 &&
          (best < 0 || weekdayAverages[i] > weekdayAverages[best])) {
        best = i;
      }
    }
    return best < 0 ? null : best;
  }
}
