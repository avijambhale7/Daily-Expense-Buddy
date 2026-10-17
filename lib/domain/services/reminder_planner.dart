import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';
import '../models/loan.dart';
import '../models/user_preferences.dart';

class PlannedReminder extends Equatable {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.day,
    required this.slot,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Notification id, stable for a given day + slot.
  final int id;

  /// Local wall-clock time the reminder should fire.
  final DateTime at;

  /// The day the reminder is about.
  final LocalDate day;

  /// 0 = primary reminder, 1.. = follow-ups.
  final int slot;
  final String title;
  final String body;

  /// Route opened when the notification is tapped.
  final String payload;

  bool get isFollowUp => slot > 0;

  @override
  List<Object?> get props => [id, at, day, slot, title, body, payload];
}

/// Computes which reminder notifications should be pending.
///
/// Reminders are scheduled as individual one-shot notifications for the next
/// [horizonDays] days, rather than one repeating notification, so that the
/// reminders of a day can be removed as soon as that day is marked complete.
/// The plan is recomputed whenever settings or day statuses change and every
/// time the app is opened.
abstract final class ReminderPlanner {
  static const int horizonDays = 14;
  static const int idBase = 100000;

  static int idFor(LocalDate day, int slot) =>
      idBase + (day.epochDay % 10000) * 10 + slot;

  static String payloadFor(LocalDate day) => '/calendar/day/${day.toIso()}';

  static List<PlannedReminder> plan({
    required DateTime now,
    required ReminderSettings settings,
    required Set<LocalDate> completedDays,
    int days = horizonDays,
  }) {
    if (!settings.enabled) return const [];
    final today = LocalDate.fromDateTime(now);
    final slots = <int>[settings.timeMinutes];
    if (settings.followUpsEnabled) {
      final followUps =
          settings.followUpMinutes
              .where((m) => m > settings.timeMinutes)
              .toSet()
              .toList()
            ..sort();
      slots.addAll(followUps.take(ReminderSettings.maxFollowUps));
    }

    final result = <PlannedReminder>[];
    for (var i = 0; i < days; i++) {
      final day = today.addDays(i);
      if (completedDays.contains(day)) continue;
      for (var s = 0; s < slots.length; s++) {
        final minutes = slots[s];
        if (settings.isQuiet(minutes)) continue;
        final at = DateTime(
          day.year,
          day.month,
          day.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (!at.isAfter(now)) continue;
        result.add(
          PlannedReminder(
            id: idFor(day, s),
            at: at,
            day: day,
            slot: s,
            title: s == 0
                ? "Time to log today's expenses"
                : "Today's expenses aren't complete yet",
            body: s == 0
                ? 'Take a few seconds to record what you spent today.'
                : 'Add anything missing or mark the day as complete.',
            payload: payloadFor(day),
          ),
        );
      }
    }
    return result;
  }

  static const int loanIdBase = 200000;

  /// Stable notification id for a loan's due-date reminder (FNV-1a, so it
  /// is the same on every run and device).
  static int loanIdFor(String loanId) {
    var h = 0x811c9dc5;
    for (final unit in loanId.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return loanIdBase + h % 100000;
  }

  /// One reminder per open loan, at the daily reminder time on its due
  /// date. A reminder that has already fired is in the past and is never
  /// planned again, so each due date is mentioned once. Nobody else is ever
  /// contacted; the reminder only appears on the user's device.
  static List<PlannedReminder> planLoanDue({
    required DateTime now,
    required ReminderSettings settings,
    required Iterable<Loan> loans,
    int days = horizonDays,
  }) {
    if (!settings.enabled) return const [];
    final today = LocalDate.fromDateTime(now);
    final last = today.addDays(days - 1);
    final minutes = settings.timeMinutes;
    final result = <PlannedReminder>[];
    for (final loan in loans) {
      final due = loan.dueDate;
      if (loan.settled || due == null || due < today || last < due) continue;
      final at = DateTime(
        due.year,
        due.month,
        due.day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (!at.isAfter(now)) continue;
      final lent = loan.direction == LoanDirection.lent;
      result.add(
        PlannedReminder(
          id: loanIdFor(loan.id),
          at: at,
          day: due,
          slot: 0,
          title: lent ? 'A loan is due back today' : 'A repayment is due today',
          body: lent
              ? 'The money you lent to ${loan.personName} is due back today.'
              : 'Your repayment to ${loan.personName} is due today.',
          payload: '/loans',
        ),
      );
    }
    return result;
  }
}
