import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';

/// What the user explicitly recorded about a day. Stored separately from
/// expenses in `users/{uid}/daily_status/{yyyy-MM-dd}`. The absence of a
/// record means the day has not been reviewed.
enum StoredDayStatus {
  /// The user confirmed all of the day's expenses are recorded.
  completed('completed'),

  /// The user confirmed they spent nothing that day.
  noExpenses('no_expenses');

  const StoredDayStatus(this.key);
  final String key;

  static StoredDayStatus? fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// The effective tracking state shown in the calendar, dashboard and used by
/// the reminder system.
enum DailyTrackingState {
  notReviewed('Not reviewed'),
  completedWithExpenses('Completed'),
  confirmedNoExpenses('No expenses');

  const DailyTrackingState(this.label);
  final String label;

  bool get isComplete => this != notReviewed;
}

class DailyStatusRecord extends Equatable {
  const DailyStatusRecord({
    required this.date,
    required this.status,
    this.updatedAt,
  });

  final LocalDate date;
  final StoredDayStatus status;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => [date, status, updatedAt];
}
