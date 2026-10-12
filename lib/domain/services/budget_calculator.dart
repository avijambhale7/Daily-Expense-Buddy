import '../../core/dates/local_date.dart';
import '../../core/money/money_math.dart';
import '../models/budget.dart';
import '../models/expense.dart';
import 'report_calculator.dart';

/// Computes monthly budget usage from recorded expenses.
///
/// A budget only counts expenses recorded in the budget's own currency, in
/// the selected calendar month, and (for category budgets) in its category.
abstract final class BudgetCalculator {
  static BudgetStatus status({
    required Budget budget,
    required Iterable<Expense> expenses,
    required LocalDate month,
    required List<int> thresholds,
  }) {
    final range = DateRange(month.startOfMonth, month.endOfMonth);
    final relevant = budget.categoryId == null
        ? expenses
        : expenses.where((e) => e.categoryId == budget.categoryId);
    final spent = ReportCalculator.totalFor(
      relevant,
      budget.currencyCode,
      range,
    );
    final used = budget.amountMinor > 0
        ? MoneyMath.divideRounded(spent * 10000, budget.amountMinor)
        : 0;
    final sorted = [...thresholds]..sort();
    int? reached;
    for (final t in sorted) {
      if (used >= t * 100) reached = t;
    }
    final warnAt = sorted
        .where((t) => t < 100)
        .fold<int?>(null, (min, t) => min == null || t < min ? t : min);
    final BudgetLevel level;
    if (used >= 10000) {
      level = BudgetLevel.exceeded;
    } else if (warnAt != null && used >= warnAt * 100) {
      level = BudgetLevel.warning;
    } else {
      level = BudgetLevel.onTrack;
    }
    return BudgetStatus(
      budget: budget,
      spentMinor: spent,
      usedBasisPoints: used,
      level: level,
      highestThresholdReached: reached,
    );
  }

  /// How much can still be spent [today] while staying within an overall
  /// monthly [budget]: (budget − spent before today) ÷ days left in the
  /// month including today, rounded down. Never negative.
  static int dailyAllowanceMinor({
    required Budget budget,
    required Iterable<Expense> expenses,
    required LocalDate today,
  }) {
    final monthStart = today.startOfMonth;
    final spentBefore = today == monthStart
        ? 0
        : ReportCalculator.totalFor(
            expenses,
            budget.currencyCode,
            DateRange(monthStart, today.addDays(-1)),
          );
    final remaining = budget.amountMinor - spentBefore;
    if (remaining <= 0) return 0;
    final daysLeft = today.endOfMonth.daysSince(today) + 1;
    return remaining ~/ daysLeft;
  }

  static List<BudgetStatus> statuses({
    required List<Budget> budgets,
    required Iterable<Expense> expenses,
    required LocalDate month,
    required List<int> thresholds,
  }) {
    final list = expenses.toList(growable: false);
    final result =
        [
          for (final b in budgets)
            status(
              budget: b,
              expenses: list,
              month: month,
              thresholds: thresholds,
            ),
        ]..sort((a, b) {
          if (a.budget.isOverall != b.budget.isOverall) {
            return a.budget.isOverall ? -1 : 1;
          }
          return b.usedBasisPoints.compareTo(a.usedBasisPoints);
        });
    return result;
  }
}
