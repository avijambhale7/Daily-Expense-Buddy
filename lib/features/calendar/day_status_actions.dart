import 'package:material_ui/material_ui.dart';

import '../../app/session/user_scope.dart';
import '../../core/dates/local_date.dart';
import '../../core/errors/app_failure.dart';
import '../../core/widgets/common.dart';
import '../../domain/models/daily_status.dart';
import '../../domain/services/tracking_status_service.dart';

/// Shared actions for recording a day's tracking status. Used by the
/// dashboard, calendar and day detail screens so they behave identically.
abstract final class DayStatusActions {
  static Future<void> markComplete(
    BuildContext context,
    LocalDate day, {
    required bool hasExpenses,
  }) => _set(
    context,
    day,
    TrackingStatusService.statusForCompletion(hasExpenses: hasExpenses),
    hasExpenses ? 'Day marked as complete' : 'Marked as a day with no expenses',
  );

  static Future<void> confirmNoExpenses(BuildContext context, LocalDate day) =>
      _set(
        context,
        day,
        StoredDayStatus.noExpenses,
        'Marked as a day with no expenses',
      );

  static Future<void> reopen(BuildContext context, LocalDate day) async {
    final repo = SessionScope.of(context).dailyStatus;
    try {
      await repo.clearStatus(day);
      if (context.mounted) showMessage(context, 'Day reopened');
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }

  static Future<void> _set(
    BuildContext context,
    LocalDate day,
    StoredDayStatus status,
    String message,
  ) async {
    final repo = SessionScope.of(context).dailyStatus;
    try {
      await repo.setStatus(day, status);
      if (context.mounted) showMessage(context, message);
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }
}
