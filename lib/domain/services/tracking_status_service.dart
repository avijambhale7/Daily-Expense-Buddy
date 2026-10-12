import '../../core/dates/local_date.dart';
import '../models/daily_status.dart';

/// Single source of truth for daily tracking state, shared by the calendar,
/// dashboard, day detail screen and reminder scheduling.
abstract final class TrackingStatusService {
  /// Combines the user's explicit record with whether the day has expenses.
  ///
  /// A day without expenses and without a record is **not** a confirmed
  /// zero-spending day; it is simply not reviewed.
  static DailyTrackingState effectiveState({
    required StoredDayStatus? stored,
    required bool hasExpenses,
  }) {
    switch (stored) {
      case null:
        return DailyTrackingState.notReviewed;
      case StoredDayStatus.completed:
      case StoredDayStatus.noExpenses:
        // If expenses were added after confirming "no expenses", the day is
        // still reviewed – but it is reported as completed with expenses.
        return hasExpenses
            ? DailyTrackingState.completedWithExpenses
            : DailyTrackingState.confirmedNoExpenses;
    }
  }

  /// The status to store when the user marks a day as complete.
  static StoredDayStatus statusForCompletion({required bool hasExpenses}) =>
      hasExpenses ? StoredDayStatus.completed : StoredDayStatus.noExpenses;

  /// Past days in the [lookbackDays] before [today] (exclusive) that are not
  /// reviewed, ignoring days before [accountStart]. Most recent first.
  static List<LocalDate> incompleteDays({
    required LocalDate today,
    required Map<LocalDate, StoredDayStatus> stored,
    required LocalDate? accountStart,
    int lookbackDays = 7,
  }) {
    final result = <LocalDate>[];
    for (var i = 1; i <= lookbackDays; i++) {
      final d = today.addDays(-i);
      if (accountStart != null && d < accountStart) break;
      if (!stored.containsKey(d)) result.add(d);
    }
    return result;
  }
}
